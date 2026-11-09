<?php

namespace App\Support;

use App\Models\Note;
use App\Models\Todo;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\DB;

/**
 * Resolves the uuid references that link and reminder rows carry.
 *
 * Every inter-item pointer in this API is a client-generated uuid, never the
 * internal bigint id, because an offline-first client only holds uuids while
 * the referenced item is still unsynced. Resolution always runs through the
 * models' OwnedByUser global scope, so a foreign or unknown uuid simply is not
 * found and callers answer 404 instead of 403.
 */
final class ItemResolver
{
    /** @return class-string<Model> */
    public static function classFor(string $type): string
    {
        return match ($type) {
            'todo' => Todo::class,
            default => Note::class,
        };
    }

    public static function typeOf(Model $item): string
    {
        return $item instanceof Todo ? 'todo' : 'note';
    }

    /**
     * The live (or trashed) row a uuid points at inside the current user.
     */
    public static function find(string $type, string $uuid, bool $withTrashed = false): ?Model
    {
        $class = self::classFor($type);
        $query = $class::query();

        if ($withTrashed && in_array(SoftDeletes::class, class_uses_recursive($class), true)) {
            $query->withTrashed();
        }

        return $query->where('uuid', $uuid)->first();
    }

    /**
     * One query per item type, whatever the number of uuids: returns the uuids
     * that resolve to a row of this type owned by the current user.
     *
     * @param  string[]  $uuids
     * @return array<string, bool>
     */
    public static function knownUuids(string $type, array $uuids, bool $withTrashed = true): array
    {
        $uuids = array_values(array_unique(array_filter($uuids, fn ($u) => is_string($u) && $u !== '')));

        if ($uuids === []) {
            return [];
        }

        $class = self::classFor($type);
        $query = $class::query();

        if ($withTrashed && in_array(SoftDeletes::class, class_uses_recursive($class), true)) {
            $query->withTrashed();
        }

        return array_fill_keys($query->whereIn('uuid', $uuids)->pluck('uuid')->all(), true);
    }

    /** @param string[] $uuids
     *  @return array<string, bool>
     */
    public static function revokedUuids(string $type, array $uuids, int $userId): array
    {
        $table = match ($type) {
            'note' => 'notes',
            'todo' => 'todos',
            default => null,
        };
        if ($table === null || $uuids === []) return [];

        $revoked = DB::table('item_shares')
            ->join($table, 'item_shares.item_id', '=', $table.'.id')
            ->where('item_shares.item_type', $type)
            ->where('item_shares.shared_with_user_id', $userId)
            ->whereNotNull('item_shares.revoked_at')
            ->whereIn($table.'.uuid', $uuids)
            ->pluck($table.'.uuid')
            ->all();

        return array_fill_keys($revoked, true);
    }

    /**
     * Batch-load rows for a set of uuids of one type, keyed "type:uuid".
     *
     * @param  string[]  $uuids
     * @return Model[]
     */
    public static function loadNodes(string $type, array $uuids): array
    {
        $uuids = array_values(array_unique(array_filter($uuids, fn ($u) => is_string($u) && $u !== '')));

        if ($uuids === []) {
            return [];
        }

        return self::classFor($type)::query()->whereIn('uuid', $uuids)->get()->all();
    }
}
