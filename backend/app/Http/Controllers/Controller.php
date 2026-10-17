<?php

namespace App\Http\Controllers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Symfony\Component\HttpKernel\Exception\HttpException;

abstract class Controller
{
    /**
     * Resolve a row by its client uuid within the authenticated user.
     *
     * The OwnedByUser global scope guarantees a foreign uuid is simply not
     * found, so callers get a 404 (not a 403) and existence never leaks.
     */
    protected function findOwned(string $class, string $uuid, bool $withTrashed = false): Model
    {
        /** @var class-string<Model> $class */
        $query = $class::query();

        if ($withTrashed && in_array(SoftDeletes::class, class_uses_recursive($class), true)) {
            $query->withTrashed();
        }

        $model = $query->where('uuid', $uuid)->first();

        if (! $model) {
            throw new HttpException(404, 'Not Found');
        }

        return $model;
    }
}
