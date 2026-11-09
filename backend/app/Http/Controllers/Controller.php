<?php

namespace App\Http\Controllers;

use App\Models\ItemShare;
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

    /**
     * Resolve an item for a destructive delete performed only by its owner.
     * The normal model scope exposes active shared rows so collaborators can
     * edit them; that visibility must never grant delete rights by itself.
     */
    protected function findOwnedForDelete(string $class, string $uuid, bool $withTrashed = false): Model
    {
        $model = $this->findOwned($class, $uuid, $withTrashed);

        if ((int) $model->user_id !== (int) auth()->id()) {
            throw new HttpException(404, 'Not Found');
        }

        return $model;
    }

    /** Reject content changes from collaborators whose grant is view-only. */
    protected function assertCanEditSharedItem(Model $item): void
    {
        if ((int) $item->user_id === (int) auth()->id()) {
            return;
        }

        $type = match ($item->getTable()) {
            'notes' => 'note',
            'todos' => 'todo',
            default => null,
        };
        $permission = $type === null ? null : ItemShare::query()
            ->where('item_type', $type)
            ->where('item_id', $item->getKey())
            ->where('shared_with_user_id', auth()->id())
            ->whereNull('revoked_at')
            ->value('permission');

        abort_unless($permission === 'editor', 403, 'This shared item is view-only.');
    }
}
