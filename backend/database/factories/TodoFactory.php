<?php

namespace Database\Factories;

use App\Models\Todo;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Todo>
 */
class TodoFactory extends Factory
{
    protected $model = Todo::class;

    public function definition(): array
    {
        return [
            'user_id' => \App\Models\User::factory(),
            'uuid' => fake()->uuid(),
            'title' => fake()->sentence(3),
            'notes' => fake()->optional()->sentence(),
            'done' => false,
            'priority' => fake()->randomElement(['low', 'normal', 'high']),
            'due_at' => null,
            'remind_at' => null,
        ];
    }
}
