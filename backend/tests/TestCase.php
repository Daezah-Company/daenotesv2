<?php

namespace Tests;

use App\Models\User;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    /**
     * Create a user and return [user, bearerToken] through the real
     * register endpoint so Sanctum wiring is exercised.
     */
    protected function registerUser(string $email = null): array
    {
        $email ??= fake()->unique()->safeEmail();

        $response = $this->postJson('/api/auth/register', [
            'name' => fake()->name(),
            'email' => $email,
            'password' => 'password1234',
        ]);

        $response->assertCreated()->assertJsonStructure(['data' => ['token', 'user']]);

        return [User::where('email', $email)->firstOrFail(), $response->json('data.token')];
    }
}
