<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_returns_token_and_user(): void
    {
        [$user, $token] = $this->registerUser();

        $this->assertNotEmpty($token);
        $this->assertDatabaseHas('users', ['email' => $user->email]);
    }

    public function test_register_rejects_duplicate_email_and_weak_password(): void
    {
        $email = fake()->unique()->safeEmail();
        $this->registerUser($email);

        $this->postJson('/api/auth/register', [
            'name' => 'Other', 'email' => $email, 'password' => 'password1234',
        ])->assertStatus(422)->assertJsonValidationErrors('email');

        $this->postJson('/api/auth/register', [
            'name' => 'Other', 'email' => fake()->unique()->safeEmail(), 'password' => 'short',
        ])->assertStatus(422)->assertJsonValidationErrors('password');
    }

    public function test_login_returns_token_and_rejects_bad_password(): void
    {
        $user = User::factory()->create(['email' => 'login@test.local']);
        $user->update(['password' => 'password1234']);

        $this->postJson('/api/auth/login', ['email' => 'login@test.local', 'password' => 'wrong'])
            ->assertStatus(422);

        $this->postJson('/api/auth/login', ['email' => 'login@test.local', 'password' => 'password1234'])
            ->assertOk()
            ->assertJsonPath('data.user.email', 'login@test.local')
            ->assertJsonStructure(['data' => ['token', 'user']]);
    }

    public function test_me_returns_authenticated_user(): void
    {
        [$user, $token] = $this->registerUser();
        $headers = ['Authorization' => "Bearer {$token}"];

        $this->getJson('/api/auth/me', $headers)
            ->assertOk()
            ->assertJsonPath('data.id', $user->id);

        $this->app['auth']->forgetGuards();
        $this->getJson('/api/auth/me')->assertStatus(401);
    }

    public function test_logout_revokes_the_current_token(): void
    {
        [, $token] = $this->registerUser();
        $headers = ['Authorization' => "Bearer {$token}"];

        $this->postJson('/api/auth/logout', [], $headers)->assertOk();

        $this->assertDatabaseCount('personal_access_tokens', 0);

        $this->app['auth']->forgetGuards();
        $this->getJson('/api/auth/me', $headers)->assertStatus(401);
    }
}
