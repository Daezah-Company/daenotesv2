<?php

namespace Tests\Feature;

use App\Models\ItemShare;
use App\Models\Note;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SharedItemAccessTest extends TestCase
{
    use RefreshDatabase;

    public function test_collaborator_can_edit_but_cannot_delete_owner_note(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $note = Note::factory()->for($owner)->create([
            'uuid' => 'shared-note-read-only',
            'title' => 'Owner title',
            'body' => 'Owner body',
        ]);
        $this->share('note', $note->id, $owner->id, $collaborator->id);
        Sanctum::actingAs($collaborator);

        $this->getJson('/api/notes/'.$note->uuid)
            ->assertOk()
            ->assertJsonPath('data.owner_user_id', $owner->id);

        $this->putJson('/api/notes/'.$note->uuid, [
            'title' => 'Overwritten',
            'body' => 'Overwritten',
        ])->assertOk()->assertJsonPath('data.title', 'Overwritten');

        $this->deleteJson('/api/notes/'.$note->uuid)->assertNotFound();
        $this->assertNotSoftDeleted('notes', ['id' => $note->id]);
        $this->assertSame('Overwritten', $note->fresh()->title);
    }

    public function test_sync_allows_collaborator_edit_to_shared_note(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $note = Note::factory()->for($owner)->create([
            'uuid' => 'shared-note-sync',
            'title' => 'Canonical owner title',
            'body' => 'Canonical owner body',
        ]);
        $this->share('note', $note->id, $owner->id, $collaborator->id);
        Sanctum::actingAs($collaborator);

        $this->postJson('/api/sync/push', [
            'notes' => [[
                'uuid' => $note->uuid,
                'title' => 'Collaborator edit',
                'body' => 'Collaborator edit body',
                'updated_at' => now()->addMinute()->toIso8601String(),
            ]],
        ])
            ->assertOk()
            ->assertJsonCount(1, 'data.accepted')
            ->assertJsonCount(0, 'data.read_only');

        $this->assertNotSoftDeleted('notes', ['id' => $note->id]);
        $this->assertSame('Collaborator edit', $note->fresh()->title);
    }

    public function test_sync_rejects_collaborator_delete_and_returns_owner_copy(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $note = Note::factory()->for($owner)->create([
            'uuid' => 'shared-note-sync-delete',
            'title' => 'Canonical owner title',
            'body' => 'Canonical owner body',
        ]);
        $this->share('note', $note->id, $owner->id, $collaborator->id);
        Sanctum::actingAs($collaborator);

        $this->postJson('/api/sync/push', [
            'deletes' => [['type' => 'note', 'uuid' => $note->uuid]],
        ])
            ->assertOk()
            ->assertJsonCount(1, 'data.read_only')
            ->assertJsonPath('data.read_only.0.server.title', 'Canonical owner title');

        $this->assertNotSoftDeleted('notes', ['id' => $note->id]);
        $this->assertSame('Canonical owner title', $note->fresh()->title);
    }

    public function test_collaborator_cannot_toggle_or_delete_owner_todo(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $todo = Todo::factory()->for($owner)->create([
            'uuid' => 'shared-todo-read-only',
            'title' => 'Owner todo',
            'done' => false,
        ]);
        $this->share('todo', $todo->id, $owner->id, $collaborator->id);
        Sanctum::actingAs($collaborator);

        $this->patchJson('/api/todos/'.$todo->uuid.'/toggle')->assertOk();
        $this->deleteJson('/api/todos/'.$todo->uuid)->assertNotFound();
        $this->assertNotSoftDeleted('todos', ['id' => $todo->id]);
        $this->assertTrue((bool) $todo->fresh()->done);
    }

    public function test_collaborator_cannot_resurrect_owner_deleted_note_or_todo(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $note = Note::factory()->for($owner)->create(['uuid' => 'deleted-shared-note']);
        $todo = Todo::factory()->for($owner)->create(['uuid' => 'deleted-shared-todo']);
        $this->share('note', $note->id, $owner->id, $collaborator->id);
        $this->share('todo', $todo->id, $owner->id, $collaborator->id);
        $note->delete();
        $todo->delete();
        Sanctum::actingAs($collaborator);

        $this->postJson('/api/notes/'.$note->uuid, [
            'uuid' => $note->uuid,
            'title' => 'Unauthorized restore',
            'body' => 'Must stay deleted',
        ])->assertNotFound();

        $this->postJson('/api/todos', [
            'uuid' => $todo->uuid,
            'title' => 'Unauthorized restore',
        ])->assertNotFound();

        $this->assertSoftDeleted('notes', ['id' => $note->id]);
        $this->assertSoftDeleted('todos', ['id' => $todo->id]);
    }

    public function test_invitee_sees_owner_identity_but_not_other_invitees(): void
    {
        $owner = User::factory()->create(['name' => 'Owner']);
        $collaborator = User::factory()->create(['name' => 'Invitee']);
        $other = User::factory()->create(['name' => 'Other invitee']);
        $note = Note::factory()->for($owner)->create(['uuid' => 'shared-note-people']);
        $this->share('note', $note->id, $owner->id, $collaborator->id);
        $this->share('note', $note->id, $owner->id, $other->id);
        Sanctum::actingAs($collaborator);

        $this->getJson('/api/collaboration/note/'.$note->uuid)
            ->assertOk()
            ->assertJsonPath('data.owner.name', 'Owner')
            ->assertJsonPath('data.owner.email', $owner->email)
            ->assertJsonPath('data.can_manage', false)
            ->assertJsonCount(0, 'data.collaborators');
    }

    public function test_owner_can_change_collaborator_access_to_view_only(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $note = Note::factory()->for($owner)->create([
            'uuid' => 'shared-note-permission',
            'title' => 'Owner copy',
        ]);
        $this->share('note', $note->id, $owner->id, $collaborator->id);
        Sanctum::actingAs($owner);

        $this->putJson('/api/collaboration/note/'.$note->uuid.'/'.$collaborator->id, [
            'permission' => 'viewer',
        ])->assertOk()->assertJsonPath('data.permission', 'viewer');

        Sanctum::actingAs($collaborator);
        $this->getJson('/api/sync/changes?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()
            ->assertJsonPath('data.notes.0.access_level', 'viewer');
        $this->getJson('/api/collaboration/note/'.$note->uuid)
            ->assertOk()
            ->assertJsonPath('data.my_permission', 'viewer');
        $this->putJson('/api/notes/'.$note->uuid, [
            'title' => 'Must not save',
            'body' => 'Must not save',
        ])->assertForbidden();
        $this->postJson('/api/sync/push', [
            'notes' => [[
                'uuid' => $note->uuid,
                'title' => 'Must not save',
                'body' => 'Must not save',
                'updated_at' => now()->addMinute()->toIso8601String(),
            ]],
        ])->assertOk()
            ->assertJsonCount(1, 'data.read_only')
            ->assertJsonPath('data.read_only.0.server.title', 'Owner copy');

        $this->assertSame('Owner copy', $note->fresh()->title);
    }

    public function test_viewer_cannot_change_or_complete_a_shared_todo(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $todo = Todo::factory()->for($owner)->create([
            'uuid' => 'shared-todo-viewer',
            'title' => 'Read-only todo',
            'done' => false,
        ]);
        $this->share('todo', $todo->id, $owner->id, $collaborator->id, 'viewer');
        Sanctum::actingAs($collaborator);

        $this->patchJson('/api/todos/'.$todo->uuid.'/toggle')->assertForbidden();
        $this->putJson('/api/todos/'.$todo->uuid, [
            'title' => 'Must stay read-only',
        ])->assertForbidden();
        $this->assertFalse((bool) $todo->fresh()->done);
        $this->assertSame('Read-only todo', $todo->fresh()->title);
    }

    public function test_collaborator_cannot_change_another_invitees_permission(): void
    {
        $owner = User::factory()->create();
        $collaborator = User::factory()->create();
        $other = User::factory()->create();
        $note = Note::factory()->for($owner)->create(['uuid' => 'shared-note-no-grant-escalation']);
        $this->share('note', $note->id, $owner->id, $collaborator->id);
        $this->share('note', $note->id, $owner->id, $other->id);
        Sanctum::actingAs($collaborator);

        $this->putJson('/api/collaboration/note/'.$note->uuid.'/'.$other->id, [
            'permission' => 'editor',
        ])->assertForbidden();
    }

    private function share(
        string $type,
        int $itemId,
        int $ownerId,
        int $collaboratorId,
        string $permission = 'editor',
    ): void {
        ItemShare::query()->create([
            'item_type' => $type,
            'item_id' => $itemId,
            'owner_user_id' => $ownerId,
            'shared_with_user_id' => $collaboratorId,
            'permission' => $permission,
        ]);
    }
}
