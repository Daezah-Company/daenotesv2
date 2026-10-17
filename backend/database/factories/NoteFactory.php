<?php

namespace Database\Factories;

use App\Models\Note;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Note>
 */
class NoteFactory extends Factory
{
    protected $model = Note::class;

    public function definition(): array
    {
        return [
            'user_id' => \App\Models\User::factory(),
            'uuid' => fake()->uuid(),
            'title' => fake()->sentence(4),
            'body' => fake()->paragraphs(2, true),
            'color' => null,
            'pinned' => false,
        ];
    }
}
