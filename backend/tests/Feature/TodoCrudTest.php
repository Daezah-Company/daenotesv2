<?php

namespace Tests\Feature;

use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TodoCrudTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        Sanctum::actingAs($this->user);
    }

    public function test_can_create_update_toggle_and_delete_a_todo(): void
    {
        $payload = [
            'uuid' => 'todo-uuid-1',
            'title' => 'Buy kopi',
            'notes' => 'single origin',
            'priority' => 'high',
            'due_at' => now()->addDay()->toIso8601String(),
            'remind_at' => now()->addHours(12)->toIso8601String(),
        ];

        $this->postJson('/api/todos', $payload)
            ->assertCreated()
            ->assertJsonPath('data.done', false)
            ->assertJsonPath('data.priority', 'high');

        $this->putJson('/api/todos/todo-uuid-1', [
            'title' => 'Buy kopi v2', 'priority' => 'low', 'notes' => null,
        ])->assertOk()->assertJsonPath('data.title', 'Buy kopi v2')->assertJsonPath('data.priority', 'low');

        $this->patchJson('/api/todos/todo-uuid-1/toggle')
            ->assertOk()
            ->assertJsonPath('data.done', true)
            ->assertJsonPath('data.done_at', fn ($v) => ! empty($v));

        $this->patchJson('/api/todos/todo-uuid-1/toggle')
            ->assertOk()
            ->assertJsonPath('data.done', false)
            ->assertJsonPath('data.done_at', null);

        $this->deleteJson('/api/todos/todo-uuid-1')->assertOk();
        $this->assertSoftDeleted('todos', ['uuid' => 'todo-uuid-1']);
    }

    public function test_index_filters_done_due_and_q(): void
    {
        Todo::factory()->for($this->user)->create(['title' => '已完成 alpha', 'due_at' => now()->subWeek()]);
        $open = Todo::factory()->for($this->user)->create(['title' => 'beta today', 'due_at' => today()]);
        $done = Todo::factory()->for($this->user)->create(['title' => 'gamma done', 'done' => true]);

        $this->getJson('/api/todos?done=false')->assertOk()
            ->assertJsonPath('data.0.done', false)
            ->assertJsonCount(2, 'data');

        $this->getJson('/api/todos?done=1')->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.uuid', $done->uuid);

        $this->getJson('/api/todos?due=overdue')->assertJsonCount(1, 'data');
        $this->getJson('/api/todos?due=today')->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.uuid', $open->uuid);
        $this->getJson('/api/todos?q=alpha')->assertJsonCount(1, 'data');
    }

    public function test_priority_is_validated(): void
    {
        $this->postJson('/api/todos', [
            'uuid' => 'bad-p', 'title' => 'x', 'priority' => 'urgent',
        ])->assertStatus(422)->assertJsonValidationErrors('priority');
    }

    public function test_duplicate_uuid_rejected(): void
    {
        $payload = ['uuid' => 'todo-dup', 'title' => 'A'];
        $this->postJson('/api/todos', $payload)->assertCreated();
        $this->postJson('/api/todos', $payload)->assertStatus(422);
    }
}
