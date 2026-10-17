<?php

namespace App\Providers;

use App\Models\Note;
use App\Models\Todo;
use Illuminate\Database\Eloquent\Relations\Relation;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        Relation::morphMap([
            'note' => Note::class,
            'todo' => Todo::class,
        ]);
    }
}
