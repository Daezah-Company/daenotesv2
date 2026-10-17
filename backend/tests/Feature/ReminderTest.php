<?php

namespace Tests\Feature;

use App\Models\Note;
use App\Models\Reminder;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ReminderTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        Sanctum::actingAs($this->user);
    }

    public function test_can_create_reminder_and_fire_it(): void
    {
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/reminders', [
            'uuid' => 'rem-1',
            'item_type' => 'todo',
            'item_uuid' => $todo->uuid,
            'title' => 'Kerjakan sebelum meeting',
            'scheduled_at' => now()->addHours(3)->toIso8601String(),
        ])->assertCreated()->assertJsonPath('data.fired_at', null);

        $this->patchJson('/api/reminders/rem-1/fire')
            ->assertOk()
            ->assertJsonPath('data.fired_at', fn ($v) => ! empty($v));

        $this->getJson('/api/reminders?fired=1')->assertJsonCount(1, 'data');
        $this->getJson('/api/reminders?upcoming=1')->assertJsonCount(0, 'data');
    }

    public function test_reminder_index_separates_upcoming_from_fired(): void
    {
        $note = Note::factory()->for($this->user)->create();
        Reminder::factory()->for($this->user)->create([
            'item_type' => 'note', 'item_uuid' => $note->uuid,
            'scheduled_at' => now()->addDay(), 'fired_at' => null,
        ]);
        Reminder::factory()->for($this->user)->create([
            'item_type' => 'note', 'item_uuid' => $note->uuid,
            'scheduled_at' => now()->subDay(), 'fired_at' => now()->subDay(),
        ]);

        $this->getJson('/api/reminders?upcoming=1')->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.fired_at', null);
        $this->getJson('/api/reminders?fired=1')->assertJsonCount(1, 'data');
        $this->getJson('/api/reminders')->assertJsonCount(2, 'data');
    }

    public function test_reminder_created_for_an_item_addressed_by_uuid(): void
    {
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/reminders', [
            'uuid' => 'rem-uuid-1', 'item_type' => 'todo', 'item_uuid' => $todo->uuid,
            'title' => 'Review', 'scheduled_at' => now()->addHour()->toIso8601String(),
        ])->assertCreated()->assertJsonPath('data.item_uuid', $todo->uuid)
            ->assertJsonMissingPath('data.item_id');

        $this->assertDatabaseHas('reminders', ['uuid' => 'rem-uuid-1', 'item_uuid' => $todo->uuid]);
    }

    public function test_reminder_item_must_exist_for_user(): void
    {
        // Regression: unknown or foreign item uuid answers 404, never 403.
        $this->postJson('/api/reminders', [
            'uuid' => 'rem-bad', 'item_type' => 'todo', 'item_uuid' => 'no-such-todo',
            'title' => 'x', 'scheduled_at' => now()->toIso8601String(),
        ])->assertNotFound();

        $this->assertSame(0, Reminder::forUser($this->user->id)->withTrashed()->count());
    }
}
