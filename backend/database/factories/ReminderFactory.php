<?php

namespace Database\Factories;

use App\Models\Reminder;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Reminder>
 */
class ReminderFactory extends Factory
{
    protected $model = Reminder::class;

    public function definition(): array
    {
        $user = User::factory()->create();

        return [
            'user_id' => $user->id,
            'uuid' => fake()->uuid(),
            'item_type' => 'todo',
            'item_uuid' => Todo::factory()->create(['user_id' => $user->id])->uuid,
            'title' => fake()->sentence(3),
            'scheduled_at' => now()->addDay(),
        ];
    }
}
