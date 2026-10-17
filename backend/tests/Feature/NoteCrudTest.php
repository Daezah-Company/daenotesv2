<?php

namespace Tests\Feature;

use App\Models\Note;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class NoteCrudTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        Sanctum::actingAs($this->user);
    }

    public function test_can_create_read_update_delete_a_note(): void
    {
        $payload = ['uuid' => 'aaaa1111-0000-0000-0000-000000000001', 'title' => 'First', 'body' => 'Hello world'];

        $this->postJson('/api/notes', $payload)
            ->assertCreated()
            ->assertJsonPath('data.uuid', $payload['uuid'])
            ->assertJsonPath('data.title', 'First');

        $this->getJson("/api/notes/{$payload['uuid']}")
            ->assertOk()
            ->assertJsonPath('data.body', 'Hello world')
            ->assertJsonPath('data.synced_at', fn ($v) => ! empty($v));

        $this->putJson("/api/notes/{$payload['uuid']}", [
            'title' => 'Edited', 'body' => 'Changed', 'pinned' => true,
        ])->assertOk()->assertJsonPath('data.title', 'Edited')->assertJsonPath('data.pinned', true);

        $this->deleteJson("/api/notes/{$payload['uuid']}")
            ->assertOk()
            ->assertJsonPath('data.deleted', true);

        $this->getJson("/api/notes/{$payload['uuid']}")->assertNotFound();
        $this->assertSoftDeleted('notes', ['uuid' => $payload['uuid']]);
    }

    public function test_duplicate_uuid_is_rejected(): void
    {
        $payload = ['uuid' => 'dup-uuid-1', 'title' => 'A', 'body' => 'B'];

        $this->postJson('/api/notes', $payload)->assertCreated();
        $this->postJson('/api/notes', $payload)->assertStatus(422)->assertJsonValidationErrors('uuid');
    }

    public function test_posting_a_previously_deleted_uuid_restores_instead_of_duplicating(): void
    {
        $payload = ['uuid' => 'revive-uuid-1', 'title' => 'A', 'body' => 'B'];

        $this->postJson('/api/notes', $payload)->assertCreated();
        $this->deleteJson('/api/notes/revive-uuid-1')->assertOk();

        $this->postJson('/api/notes', ['uuid' => 'revive-uuid-1', 'title' => 'A2', 'body' => 'B2'])
            ->assertOk()
            ->assertJsonPath('data.title', 'A2');

        $this->assertSame(1, Note::forUser($this->user->id)->count());
    }

    public function test_index_filters_sorts_and_paginates(): void
    {
        Note::factory()->for($this->user)->create(['title' => 'Laravel tips', 'body' => 'eloquent']);
        Note::factory()->for($this->user)->create(['title' => 'Groceries', 'body' => 'milk', 'pinned' => true]);

        $this->getJson('/api/notes?q=Laravel')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.title', 'Laravel tips');

        $this->getJson('/api/notes?sort=-pinned,title')
            ->assertOk()
            ->assertJsonPath('data.0.title', 'Groceries');

        $this->getJson('/api/notes?per_page=1')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonStructure(['data', 'links', 'meta' => ['current_page', 'total']]);
    }

    public function test_archive_and_restore_flow(): void
    {
        $note = Note::factory()->for($this->user)->create();

        $this->postJson("/api/notes/{$note->uuid}/archive")
            ->assertOk()
            ->assertJsonPath('data.archived_at', fn ($v) => ! empty($v));

        $this->getJson('/api/notes')->assertJsonPath('data.0.archived_at', fn ($v) => ! empty($v));
        $this->getJson('/api/notes?archived=false')->assertJsonCount(0, 'data');
        $this->getJson('/api/notes?archived=1')->assertJsonCount(1, 'data');

        $this->postJson("/api/notes/{$note->uuid}/restore")
            ->assertOk()
            ->assertJsonPath('data.archived_at', null);
    }

    public function test_updated_since_includes_soft_deleted_rows(): void
    {
        $keep = Note::factory()->for($this->user)->create(['title' => 'keep']);
        $gone = Note::factory()->for($this->user)->create(['title' => 'gone']);
        $gone->delete();

        $past = urlencode(now()->subMinute()->toIso8601String());
        $response = $this->getJson("/api/notes?updated_since={$past}")->assertOk();

        $uuids = collect($response->json('data'))->pluck('uuid');
        $this->assertTrue($uuids->contains($keep->uuid));
        $this->assertTrue($uuids->contains($gone->uuid));

        $future = urlencode(now()->addMinute()->toIso8601String());
        $this->getJson("/api/notes?updated_since={$future}")->assertJsonCount(0, 'data');
    }

    public function test_validation_requires_title_and_body(): void
    {
        $this->postJson('/api/notes', ['uuid' => 'x1', 'title' => ''])->assertStatus(422);
        $this->postJson('/api/notes', ['title' => 'no uuid'])->assertStatus(422);
    }
}
