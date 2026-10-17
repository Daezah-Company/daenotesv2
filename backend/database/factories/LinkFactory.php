<?php

namespace Database\Factories;

use App\Models\Link;
use App\Models\Note;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Link>
 */
class LinkFactory extends Factory
{
    protected $model = Link::class;

    public function definition(): array
    {
        $user = User::factory()->create();

        return [
            'user_id' => $user->id,
            'uuid' => fake()->uuid(),
            'source_type' => 'note',
            'source_uuid' => Note::factory()->create(['user_id' => $user->id])->uuid,
            'target_type' => 'todo',
            'target_uuid' => Todo::factory()->create(['user_id' => $user->id])->uuid,
            'label' => null,
        ];
    }

    public function between(mixed $source, mixed $target): static
    {
        return $this->state(fn () => [
            'user_id' => $source->user_id,
            'source_type' => $this->typeFor($source),
            'source_uuid' => $source->uuid,
            'target_type' => $this->typeFor($target),
            'target_uuid' => $target->uuid,
        ]);
    }

    protected function typeFor(mixed $model): string
    {
        return $model instanceof Todo ? 'todo' : 'note';
    }
}
