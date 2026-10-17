<?php

namespace Tests\Feature;

use App\Models\Link;
use App\Models\Note;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SyncTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        Sanctum::actingAs($this->user);
    }

    public function test_push_is_idempotent_for_repeated_uuid(): void
    {
        $payload = ['notes' => [
            ['uuid' => 'sync-note-1', 'title' => 'Offline note', 'body' => 'created offline', 'updated_at' => now()->toIso8601String()],
        ]];

        $this->postJson('/api/sync/push', $payload)
            ->assertOk()
            ->assertJsonPath('data.accepted.0.uuid', 'sync-note-1')
            ->assertJsonCount(0, 'data.conflicts');

        // Same uuid pushed again — must update, never duplicate.
        $this->postJson('/api/sync/push', [
            'notes' => [
                ['uuid' => 'sync-note-1', 'title' => 'Offline note v2', 'body' => 'edited offline', 'updated_at' => now()->addMinute()->toIso8601String()],
            ],
        ])->assertOk()->assertJsonCount(1, 'data.accepted')->assertJsonCount(0, 'data.conflicts');

        $this->assertSame(1, Note::forUser($this->user->id)->withTrashed()->count());
        $this->assertSame('Offline note v2', Note::findByUuid('sync-note-1')->title);
        $this->assertNotNull(Note::findByUuid('sync-note-1')->synced_at);
    }

    public function test_push_reports_conflict_when_server_row_is_newer(): void
    {
        $note = Note::factory()->for($this->user)->create(['uuid' => 'sync-conflict-1', 'title' => 'Server version']);

        $stale = $note->updated_at->copy()->subHour()->toIso8601String();

        $this->postJson('/api/sync/push', [
            'notes' => [['uuid' => 'sync-conflict-1', 'title' => 'Old client copy', 'body' => 'stale', 'updated_at' => $stale]],
        ])
            ->assertOk()
            ->assertJsonCount(1, 'data.conflicts')
            ->assertJsonPath('data.conflicts.0.type', 'note')
            ->assertJsonPath('data.conflicts.0.uuid', 'sync-conflict-1')
            ->assertJsonPath('data.conflicts.0.server.title', 'Server version');

        // The conflicting push must not overwrite the server row.
        $this->assertSame('Server version', $note->fresh()->title);
    }

    public function test_push_applies_deletes_idempotently(): void
    {
        $note = Note::factory()->for($this->user)->create(['uuid' => 'sync-del-1']);
        Todo::factory()->for($this->user)->create(['uuid' => 'sync-del-2']);

        $this->postJson('/api/sync/push', [
            'deletes' => [
                ['type' => 'note', 'uuid' => 'sync-del-1'],
                ['type' => 'todos', 'uuid' => 'sync-del-2'],
                ['type' => 'note', 'uuid' => 'never-existed'],
            ],
        ])->assertOk()->assertJsonCount(3, 'data.accepted');

        $this->assertSoftDeleted('notes', ['uuid' => 'sync-del-1']);
        $this->assertSoftDeleted('todos', ['uuid' => 'sync-del-2']);

        // Replaying the same delete changes is still accepted.
        $this->postJson('/api/sync/push', [
            'deletes' => [['type' => 'note', 'uuid' => 'sync-del-1']],
        ])->assertOk()->assertJsonCount(1, 'data.accepted');
    }

    public function test_changes_returns_updated_rows_deletes_and_server_time(): void
    {
        $note = Note::factory()->for($this->user)->create(['title' => 'alive']);
        $gone = Note::factory()->for($this->user)->create(['title' => 'gone', 'uuid' => 'gone-note-uuid']);
        $todo = Todo::factory()->for($this->user)->create();
        $link = Link::factory()->for($this->user)->between($note, $todo)->create();
        $gone->delete();

        $response = $this->getJson('/api/sync/changes?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()
            ->assertJsonStructure(['data' => ['notes', 'todos', 'links', 'reminders', 'deleted', 'server_time']])
            ->assertJsonPath('data.deleted.notes', ['gone-note-uuid']);

        $this->assertSame($note->uuid, $response->json('data.notes.0.uuid'));
        $this->assertCount(1, $response->json('data.todos'));
        $this->assertCount(1, $response->json('data.links'));
        $this->assertCount(0, $response->json('data.reminders'));

        // A push then a newer fetch marks rows as synced; old since returns everything.
        $this->getJson('/api/sync/changes')->assertOk();
    }

    public function test_push_can_create_and_delete_links_and_reminders(): void
    {
        $note = Note::factory()->for($this->user)->create(['uuid' => 'p-note']);
        $todo = Todo::factory()->for($this->user)->create(['uuid' => 'p-todo']);

        $this->postJson('/api/sync/push', [
            'links' => [[
                'uuid' => 'p-link', 'source_type' => 'note', 'source_uuid' => $note->uuid,
                'target_type' => 'todo', 'target_uuid' => $todo->uuid, 'label' => 'synced link',
            ]],
            'reminders' => [[
                'uuid' => 'p-reminder', 'item_type' => 'todo', 'item_uuid' => $todo->uuid,
                'title' => 'ping', 'scheduled_at' => now()->addHour()->toIso8601String(),
            ]],
        ])->assertOk()->assertJsonCount(2, 'data.accepted');

        $this->assertDatabaseHas('links', ['uuid' => 'p-link', 'source_uuid' => 'p-note', 'target_uuid' => 'p-todo']);
        $this->assertDatabaseHas('reminders', ['uuid' => 'p-reminder', 'item_uuid' => 'p-todo']);

        $this->postJson('/api/sync/push', [
            'deletes' => [['type' => 'link', 'uuid' => 'p-link'], ['type' => 'reminder', 'uuid' => 'p-reminder']],
        ])->assertOk();

        $this->assertSoftDeleted('links', ['uuid' => 'p-link']);
        $this->assertSoftDeleted('reminders', ['uuid' => 'p-reminder']);
    }

    public function test_push_accepts_a_link_whose_targets_are_pushed_in_the_same_request(): void
    {
        // Regression: an offline client sends one batch where a link references a
        // note and a todo it also creates in that batch, in any key order. Here
        // the link comes first on purpose — it must still succeed.
        $this->postJson('/api/sync/push', [
            'links' => [[
                'uuid' => 'o-link', 'source_type' => 'note', 'source_uuid' => 'o-note',
                'target_type' => 'todo', 'target_uuid' => 'o-todo', 'label' => 'offline thread',
            ]],
            'notes' => [[
                'uuid' => 'o-note', 'title' => 'Created offline', 'body' => 'no server id yet',
                'updated_at' => now()->toIso8601String(),
            ]],
            'todos' => [[
                'uuid' => 'o-todo', 'title' => 'Todo offline', 'priority' => 'high',
                'updated_at' => now()->toIso8601String(),
            ]],
            'reminders' => [[
                'uuid' => 'o-rem', 'item_type' => 'todo', 'item_uuid' => 'o-todo',
                'title' => 'ingat', 'scheduled_at' => now()->addHour()->toIso8601String(),
            ]],
        ])
            ->assertOk()
            ->assertJsonCount(4, 'data.accepted')
            ->assertJsonCount(0, 'data.conflicts');

        $this->assertDatabaseHas('links', ['uuid' => 'o-link', 'source_uuid' => 'o-note', 'target_uuid' => 'o-todo']);
        $this->assertDatabaseHas('reminders', ['uuid' => 'o-rem', 'item_uuid' => 'o-todo']);

        // The pushed edge is immediately visible in the graph, keyed by uuid.
        $graph = $this->getJson('/api/graph?depth=2&root=o-note')->assertOk();
        $this->assertCount(2, $graph->json('data.nodes'));
        $this->assertSame('o-todo', $graph->json('data.edges.0.target_uuid'));
    }

    public function test_push_rejects_a_link_referencing_a_uuid_the_server_has_never_seen(): void
    {
        $note = Note::factory()->for($this->user)->create(['uuid' => 'known-note']);

        $this->postJson('/api/sync/push', [
            'links' => [[
                'uuid' => 'ghost-link', 'source_type' => 'note', 'source_uuid' => $note->uuid,
                'target_type' => 'todo', 'target_uuid' => 'ghost-todo',
            ]],
        ])->assertStatus(422)->assertJsonValidationErrors('links.0.target_uuid');

        $this->assertSame(0, Link::forUser($this->user->id)->withTrashed()->count());
    }

    public function test_push_accepts_a_link_to_a_target_deleted_in_the_same_request(): void
    {
        $note = Note::factory()->for($this->user)->create(['uuid' => 'soon-gone']);

        $this->postJson('/api/sync/push', [
            'links' => [[
                'uuid' => 'gone-link', 'source_type' => 'note', 'source_uuid' => 'soon-gone',
                'target_type' => 'note', 'target_uuid' => 'soon-gone-alt',
            ]],
            'notes' => [[
                'uuid' => 'soon-gone-alt', 'title' => 'About to go', 'body' => 'x',
            ]],
            'deletes' => [['type' => 'note', 'uuid' => 'soon-gone-alt']],
        ])->assertOk()->assertJsonCount(3, 'data.accepted');

        $this->assertSoftDeleted('notes', ['uuid' => 'soon-gone-alt']);
        $this->assertDatabaseHas('links', ['uuid' => 'gone-link', 'target_uuid' => 'soon-gone-alt']);
    }
}
