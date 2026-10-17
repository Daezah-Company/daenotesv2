<?php

namespace Tests\Feature;

use App\Models\Reminder;
use App\Models\Todo;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Regression guard for the timezone defect: an ISO8601 instant carrying a real
 * offset such as "+07:00" must be stored as the same UTC instant, never the
 * wall-clock time with the offset silently dropped.
 */
class TimezoneTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        Sanctum::actingAs($this->user);
    }

    public function test_reminder_plus_seven_offset_becomes_utc_instant_in_db_and_response(): void
    {
        $todo = Todo::factory()->for($this->user)->create();

        $response = $this->postJson('/api/reminders', [
            'uuid' => 'tz-rem-offset',
            'item_type' => 'todo',
            'item_uuid' => $todo->uuid,
            'title' => 'Meeting reminder',
            'scheduled_at' => '2026-10-18T18:00:00+07:00',
        ])->assertCreated();

        // 18:00 at +07:00 is 11:00 UTC. The offset must be honoured, not dropped.
        $response->assertJsonPath('data.scheduled_at', '2026-10-18T11:00:00Z');
        $this->assertDatabaseHas('reminders', [
            'uuid' => 'tz-rem-offset',
            'scheduled_at' => '2026-10-18 11:00:00',
        ]);

        // The stored instant round-trips back to the exact instant the client sent.
        $stored = Reminder::findByUuid('tz-rem-offset')->scheduled_at;
        $this->assertSame(
            Carbon::parse('2026-10-18T18:00:00+07:00')->getTimestamp(),
            $stored->getTimestamp(),
        );
    }

    public function test_reminder_z_input_is_unchanged(): void
    {
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/reminders', [
            'uuid' => 'tz-rem-z', 'item_type' => 'todo', 'item_uuid' => $todo->uuid,
            'title' => 'Zulu', 'scheduled_at' => '2026-10-18T11:00:00Z',
        ])->assertCreated()->assertJsonPath('data.scheduled_at', '2026-10-18T11:00:00Z');

        $this->assertDatabaseHas('reminders', [
            'uuid' => 'tz-rem-z', 'scheduled_at' => '2026-10-18 11:00:00',
        ]);
    }

    public function test_naive_string_is_treated_as_the_documented_utc_instant(): void
    {
        $todo = Todo::factory()->for($this->user)->create();

        $this->postJson('/api/reminders', [
            'uuid' => 'tz-rem-naive', 'item_type' => 'todo', 'item_uuid' => $todo->uuid,
            'title' => 'Naive', 'scheduled_at' => '2026-10-18 18:00:00',
        ])->assertCreated()->assertJsonPath('data.scheduled_at', '2026-10-18T18:00:00Z');

        // Interpreted as UTC, never shifted by any guessed local zone.
        $this->assertDatabaseHas('reminders', [
            'uuid' => 'tz-rem-naive', 'scheduled_at' => '2026-10-18 18:00:00',
        ]);
    }

    public function test_todo_due_at_offset_survives_put(): void
    {
        $todo = Todo::factory()->for($this->user)->create(['uuid' => 'tz-todo-put']);

        $this->putJson('/api/todos/tz-todo-put', [
            'title' => 'Renovate',
            'due_at' => '2026-10-18T18:00:00+07:00',
            'remind_at' => '2026-10-18T19:30:00+07:00',
        ])
            ->assertOk()
            ->assertJsonPath('data.due_at', '2026-10-18T11:00:00Z')
            ->assertJsonPath('data.remind_at', '2026-10-18T12:30:00Z');

        $this->assertDatabaseHas('todos', [
            'uuid' => 'tz-todo-put',
            'due_at' => '2026-10-18 11:00:00',
            'remind_at' => '2026-10-18 12:30:00',
        ]);
    }

    public function test_todo_due_at_offset_survives_sync_push_then_pull(): void
    {
        $this->postJson('/api/sync/push', [
            'todos' => [[
                'uuid' => 'tz-todo-sync',
                'title' => 'Synced with offset',
                'due_at' => '2026-10-18T18:00:00+07:00',
                'updated_at' => '2026-10-18T18:00:00+07:00',
            ]],
        ])->assertOk()->assertJsonCount(1, 'data.accepted');

        $this->assertDatabaseHas('todos', [
            'uuid' => 'tz-todo-sync',
            'due_at' => '2026-10-18 11:00:00',
        ]);

        // Pull it back; the same instant must come out, offset-explicit as "Z".
        // A far-past since reliably includes the row regardless of wall-clock now().
        $this->getJson('/api/sync/changes?since='.urlencode('2000-01-01T00:00:00Z'))
            ->assertOk()
            ->assertJsonPath('data.todos.0.due_at', '2026-10-18T11:00:00Z');
    }

    public function test_sync_changes_since_offset_filter_compares_the_right_instant(): void
    {
        $base = ['item_type' => 'todo', 'item_uuid' => 'ignored', 'title' => 'x', 'scheduled_at' => '2026-10-18 10:00:00'];

        // Two reminders with controlled UTC updated_at instants.
        $morning = Reminder::factory()->for($this->user)->create([...$base, 'uuid' => 'tz-rem-morning']);
        $afternoon = Reminder::factory()->for($this->user)->create([...$base, 'uuid' => 'tz-rem-afternoon']);

        $morning->updated_at = Carbon::parse('2026-10-18 12:00:00', 'UTC');
        $morning->saveQuietly();
        $afternoon->updated_at = Carbon::parse('2026-10-18 12:30:00', 'UTC');
        $afternoon->saveQuietly();

        // 17:00+07:00 == 10:00Z: both reminders are newer.
        $this->getJson('/api/sync/changes?since='.urlencode('2026-10-18T17:00:00+07:00'))
            ->assertOk()->assertJsonCount(2, 'data.reminders');

        // 19:00+07:00 == 12:00Z: only the 12:30Z reminder is strictly newer.
        // A dropped-offset bug would read this as 19:00Z and return zero rows.
        $response = $this->getJson('/api/sync/changes?since='.urlencode('2026-10-18T19:00:00+07:00'))
            ->assertOk()->assertJsonCount(1, 'data.reminders');
        $this->assertSame('tz-rem-afternoon', $response->json('data.reminders.0.uuid'));

        // 21:00+07:00 == 14:00Z: neither is newer.
        $this->getJson('/api/sync/changes?since='.urlencode('2026-10-18T21:00:00+07:00'))
            ->assertOk()->assertJsonCount(0, 'data.reminders');
    }
}
