<?php

namespace Tests\Feature;

use App\Models\Link;
use App\Models\Note;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class LinkTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        Sanctum::actingAs($this->user);
    }

    public function test_can_create_link_and_list_one_hop_neighbours(): void
    {
        $note = Note::factory()->for($this->user)->create();
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/links', [
            'uuid' => 'link-uuid-1',
            'source_type' => 'note',
            'source_uuid' => $note->uuid,
            'target_type' => 'todo',
            'target_uuid' => $todo->uuid,
            'label' => 'leads to',
        ])->assertCreated()
            ->assertJsonPath('data.label', 'leads to')
            ->assertJsonPath('data.source_uuid', $note->uuid)
            ->assertJsonPath('data.target_uuid', $todo->uuid)
            ->assertJsonMissingPath('data.source_id')
            ->assertJsonMissingPath('data.id');

        $this->getJson("/api/links?item_type=note&item_uuid={$note->uuid}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.target_uuid', $todo->uuid);

        $this->getJson("/api/links?item_type=todo&item_uuid={$todo->uuid}")
            ->assertOk()
            ->assertJsonCount(1, 'data');

        // The legacy filter name still works, but it carries a uuid too.
        $this->getJson("/api/links?item_type=note&item_id={$note->uuid}")->assertJsonCount(1, 'data');

        $this->assertSame($note->uuid, Link::findByUuid('link-uuid-1')->source_uuid);
    }

    public function test_linking_items_by_uuid_never_needs_an_internal_id(): void
    {
        // Regression: the client is offline-first, so it only ever holds uuids.
        $note = Note::factory()->for($this->user)->create();
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/links', [
            'uuid' => 'link-by-uuid-1',
            'source_type' => 'note', 'source_uuid' => $note->uuid,
            'target_type' => 'todo', 'target_uuid' => $todo->uuid,
        ])->assertCreated()->assertJsonPath('data.uuid', 'link-by-uuid-1');

        $this->assertDatabaseHas('links', [
            'uuid' => 'link-by-uuid-1',
            'user_id' => $this->user->id,
            'source_uuid' => $note->uuid,
            'target_uuid' => $todo->uuid,
        ]);
    }

    public function test_unknown_endpoint_uuid_returns_404_and_stores_nothing(): void
    {
        // Regression: an unresolvable uuid answers 404, never 403 and never 422.
        $note = Note::factory()->for($this->user)->create();

        $this->postJson('/api/links', [
            'uuid' => 'link-ghost', 'source_type' => 'note', 'source_uuid' => 'never-seen-uuid',
            'target_type' => 'todo', 'target_uuid' => $note->uuid,
        ])->assertNotFound()->assertJsonStructure(['message']);

        $this->postJson('/api/links', [
            'uuid' => 'link-ghost', 'source_type' => 'note', 'source_uuid' => $note->uuid,
            'target_type' => 'note', 'target_uuid' => 'missing-todo-uuid',
        ])->assertNotFound();

        $this->assertSame(0, Link::forUser($this->user->id)->withTrashed()->count());
    }

    public function test_integer_ids_are_no_longer_accepted(): void
    {
        $note = Note::factory()->for($this->user)->create();
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/links', [
            'uuid' => 'link-legacy', 'source_type' => 'note', 'source_id' => $note->id,
            'target_type' => 'todo', 'target_id' => $todo->id,
        ])->assertStatus(422)->assertJsonValidationErrors(['source_uuid', 'target_uuid']);
    }

    public function test_duplicate_link_is_rejected(): void
    {
        $a = Note::factory()->for($this->user)->create();
        $b = Note::factory()->for($this->user)->create();

        $payload = [
            'uuid' => 'link-dup-1',
            'source_type' => 'note', 'source_uuid' => $a->uuid,
            'target_type' => 'note', 'target_uuid' => $b->uuid,
        ];

        $this->postJson('/api/links', $payload)->assertCreated();
        $this->postJson('/api/links', [...$payload, 'uuid' => 'link-dup-2'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('source_uuid');

        $this->assertSame(1, Link::forUser($this->user->id)->withTrashed()->count());
    }

    public function test_linking_deleted_pair_revives_instead_of_hit_unique_index(): void
    {
        $a = Note::factory()->for($this->user)->create();
        $b = Todo::factory()->for($this->user)->create();

        $payload = [
            'uuid' => 'link-revive-1',
            'source_type' => 'note', 'source_uuid' => $a->uuid,
            'target_type' => 'todo', 'target_uuid' => $b->uuid,
        ];

        $this->postJson('/api/links', $payload)->assertCreated();
        $this->deleteJson('/api/links/link-revive-1')->assertOk();

        $this->postJson('/api/links', $payload)
            ->assertOk()
            ->assertJsonPath('data.uuid', 'link-revive-1');

        $this->assertSame(1, Link::forUser($this->user->id)->withTrashed()->count());
    }

    public function test_relinking_a_deleted_pair_with_a_new_uuid_revives_the_trashed_row(): void
    {
        // The unique index spans soft-deleted rows, so a fresh uuid must reuse
        // the trashed pair instead of crashing on the constraint.
        $a = Note::factory()->for($this->user)->create();
        $b = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/links', [
            'uuid' => 'link-revive-2',
            'source_type' => 'note', 'source_uuid' => $a->uuid,
            'target_type' => 'todo', 'target_uuid' => $b->uuid,
        ])->assertCreated();

        $this->deleteJson('/api/links/link-revive-2')->assertOk();

        $this->postJson('/api/links', [
            'uuid' => 'link-revive-3',
            'source_type' => 'note', 'source_uuid' => $a->uuid,
            'target_type' => 'todo', 'target_uuid' => $b->uuid,
        ])->assertOk()->assertJsonPath('data.uuid', 'link-revive-3');

        $this->assertSame(1, Link::forUser($this->user->id)->withTrashed()->count());
        $this->assertDatabaseHas('links', ['uuid' => 'link-revive-3', 'deleted_at' => null]);
        $this->assertDatabaseMissing('links', ['uuid' => 'link-revive-2']);
    }

    public function test_self_link_and_missing_endpoints_rejected(): void
    {
        $note = Note::factory()->for($this->user)->create();

        $this->postJson('/api/links', [
            'uuid' => 'link-self', 'source_type' => 'note', 'source_uuid' => $note->uuid,
            'target_type' => 'note', 'target_uuid' => $note->uuid,
        ])->assertStatus(422)->assertJsonValidationErrors('target_uuid');

        $this->assertSame(0, Link::forUser($this->user->id)->withTrashed()->count());
    }

    public function test_deleted_item_cannot_be_linked(): void
    {
        $note = Note::factory()->for($this->user)->create();
        $todo = Todo::factory()->for($this->user)->create();
        $todo->delete();

        $this->postJson('/api/links', [
            'uuid' => 'link-dead-target', 'source_type' => 'note', 'source_uuid' => $note->uuid,
            'target_type' => 'todo', 'target_uuid' => $todo->uuid,
        ])->assertNotFound();
    }

    public function test_delete_removes_link_from_neighbour_listing(): void
    {
        $note = Note::factory()->for($this->user)->create();
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/links', [
            'uuid' => 'link-del-1', 'source_type' => 'note', 'source_uuid' => $note->uuid,
            'target_type' => 'todo', 'target_uuid' => $todo->uuid,
        ])->assertCreated();

        $this->deleteJson('/api/links/link-del-1')->assertOk();

        $this->getJson("/api/links?item_type=note&item_uuid={$note->uuid}")->assertJsonCount(0, 'data');
    }
}
