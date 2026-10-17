<?php

namespace Tests\Feature;

use App\Models\Link;
use App\Models\Note;
use App\Models\Reminder;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CrossUserIsolationTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_b_cannot_touch_any_user_a_resource_by_uuid(): void
    {
        $a = User::factory()->create();
        $b = User::factory()->create();

        $noteA = Note::factory()->for($a)->create(['uuid' => 'a-note']);
        $todoA = Todo::factory()->for($a)->create(['uuid' => 'a-todo']);
        $noteB = Note::factory()->for($b)->create();
        $linkA = Link::factory()->for($a)->between($noteA, $todoA)->create(['uuid' => 'a-link']);
        $reminderA = Reminder::factory()->for($a)->create(['uuid' => 'a-rem', 'item_type' => 'note', 'item_uuid' => $noteA->uuid]);

        Sanctum::actingAs($b);

        $this->getJson('/api/notes/a-note')->assertNotFound();
        $this->putJson('/api/notes/a-note', ['title' => 'hijack', 'body' => 'x'])->assertNotFound();
        $this->deleteJson('/api/notes/a-note')->assertNotFound();
        $this->postJson('/api/notes/a-note/archive')->assertNotFound();

        $this->putJson('/api/todos/a-todo', ['title' => 'hijack'])->assertNotFound();
        $this->patchJson('/api/todos/a-todo/toggle')->assertNotFound();
        $this->deleteJson('/api/todos/a-todo')->assertNotFound();

        $this->deleteJson('/api/links/a-link')->assertNotFound();
        $this->patchJson('/api/reminders/a-rem/fire')->assertNotFound();

        // Nothing was mutated for user A.
        $this->assertSame('a-note', Note::forUser($a->id)->firstWhere('uuid', 'a-note')->uuid);
        $this->assertNull(Note::forUser($a->id)->firstWhere('uuid', 'a-note')->deleted_at);
        $this->assertDatabaseHas('todos', ['uuid' => 'a-todo', 'deleted_at' => null]);
        $this->assertDatabaseHas('links', ['uuid' => 'a-link', 'deleted_at' => null]);
        $this->assertDatabaseHas('reminders', ['uuid' => 'a-rem', 'fired_at' => null]);

        // B still owns their own rows.
        $this->getJson("/api/notes/{$noteB->uuid}")->assertOk();
    }

    public function test_index_endpoints_only_show_own_rows(): void
    {
        $a = User::factory()->create();
        $b = User::factory()->create();

        Note::factory()->for($a)->count(3)->create(['title' => 'private A']);
        Note::factory()->for($b)->count(2)->create(['title' => 'private B']);

        Sanctum::actingAs($b);

        $this->getJson('/api/notes?per_page=50')->assertJsonCount(2, 'data');

        $since = urlencode(now()->subMinute()->toIso8601String());
        $this->getJson("/api/notes?updated_since={$since}")->assertJsonCount(2, 'data');
        $this->getJson("/api/sync/changes?since={$since}")
            ->assertOk()
            ->assertJsonCount(2, 'data.notes');

        // Graph never exposes A's links.
        $noteA = Note::forUser($a->id)->first();
        $todoA = Todo::factory()->for($a)->create();
        Link::factory()->for($a)->between($noteA, $todoA)->create();

        $this->getJson('/api/graph')->assertJsonCount(0, 'data.edges');
        $this->getJson("/api/graph?root={$noteA->uuid}")->assertNotFound();
    }

    public function test_sync_push_with_foreign_uuid_creates_own_copy_instead_of_editing(): void
    {
        $a = User::factory()->create();
        Note::factory()->for($a)->create(['uuid' => 'shared-uuid', 'title' => 'A original']);

        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/sync/push', [
            'notes' => [['uuid' => 'shared-uuid', 'title' => 'B copy', 'body' => 'mine']],
        ])->assertOk()->assertJsonCount(1, 'data.accepted')->assertJsonCount(0, 'data.conflicts');

        // A's row untouched; B now owns a row with the same uuid.
        $this->assertSame('A original', Note::forUser($a->id)->firstWhere('uuid', 'shared-uuid')->title);
        $this->assertSame('B copy', Note::query()->firstWhere('uuid', 'shared-uuid')->title);
    }

    public function test_link_store_rejects_endpoints_from_another_user(): void
    {
        $a = User::factory()->create();
        $noteA = Note::factory()->for($a)->create(['uuid' => 'a-side-note']);
        $todoA = Todo::factory()->for($a)->create(['uuid' => 'a-side-todo']);

        Sanctum::actingAs(User::factory()->create());

        // A's uuids are simply not resolvable inside B's scope: 404, no leak.
        $this->postJson('/api/links', [
            'uuid' => 'steal-link', 'source_type' => 'note', 'source_uuid' => $noteA->uuid,
            'target_type' => 'todo', 'target_uuid' => $todoA->uuid,
        ])->assertNotFound();

        $this->assertDatabaseMissing('links', ['uuid' => 'steal-link']);

        $this->postJson('/api/reminders', [
            'uuid' => 'steal-rem', 'item_type' => 'note', 'item_uuid' => $noteA->uuid,
            'title' => 'x', 'scheduled_at' => now()->toIso8601String(),
        ])->assertNotFound();
    }
}
