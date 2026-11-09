<?php

namespace App\Http\Controllers;

use App\Http\Requests\Sync\SyncPushRequest;
use App\Http\Resources\LinkResource;
use App\Http\Resources\NoteResource;
use App\Http\Resources\ReminderResource;
use App\Http\Resources\TodoResource;
use App\Models\Link;
use App\Models\ItemShare;
use App\Models\Note;
use App\Models\Reminder;
use App\Models\Todo;
use App\Models\Scopes\OwnedByUserScope;
use App\Support\Timestamp;
use App\Support\ItemResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SyncController extends Controller
{
    private const TYPES = [
        'notes' => ['model' => Note::class, 'resource' => NoteResource::class, 'label' => 'note'],
        'todos' => ['model' => Todo::class, 'resource' => TodoResource::class, 'label' => 'todo'],
        'links' => ['model' => Link::class, 'resource' => LinkResource::class, 'label' => 'link'],
        'reminders' => ['model' => Reminder::class, 'resource' => ReminderResource::class, 'label' => 'reminder'],
    ];

    /**
     * Buckets applied in dependency order, always items before the edges and
     * reminders that point at them. The push loop walks this list, not the
     * client's JSON key order, so a link pushed before its note and todo in the
     * same request still lands on rows that exist. References themselves are
     * uuid-keyed, so nothing here ever needs a server-side integer id.
     */
    private const PUSH_ORDER = ['notes', 'todos', 'links', 'reminders'];

    public function changes(Request $request): JsonResponse
    {
        $request->validate(['since' => ['sometimes', 'string']]);

        $since = Timestamp::parse('since', $request->input('since'));

        $changes = [];
        $deleted = [];

        foreach (self::TYPES as $bucket => $meta) {
            $model = $meta['model'];

            $query = $model::query();
            $deadQuery = $model::withTrashed()->whereNotNull('deleted_at');

            if ($since) {
                $query->where('updated_at', '>', $since);
                $deadQuery->where('updated_at', '>', $since);
            }

            $changes[$bucket] = $meta['resource']::collection($query->get())->resolve();
            $deleted[$bucket] = $deadQuery->pluck('uuid')->all();
        }

        // A revoked collaborator loses the server row from their ownership
        // scope. Send a tombstone so their offline mirror drops that copy.
        $revoked = ItemShare::query()
            ->where('shared_with_user_id', $request->user()->id)
            ->whereNotNull('revoked_at')
            ->when($since, fn ($query) => $query->where('revoked_at', '>', $since))
            ->get(['item_type', 'item_id']);
        foreach ($revoked->groupBy('item_type') as $type => $shares) {
            $model = $type === 'note' ? Note::class : Todo::class;
            $bucket = $type === 'note' ? 'notes' : 'todos';
            $deleted[$bucket] = array_values(array_unique([
                ...$deleted[$bucket],
                ...$model::withoutGlobalScopes()->whereIn('id', $shares->pluck('item_id'))->pluck('uuid')->all(),
            ]));
        }

        // Sharing permission changes are tracked by item_shares.updated_at,
        // not by the note/todo content timestamp. Include those rows in the
        // delta so a collaborator's offline mirror promptly learns that an
        // owner switched the grant between viewer and editor.
        $permissionChanges = ItemShare::query()
            ->where('shared_with_user_id', $request->user()->id)
            ->whereNull('revoked_at')
            // Inclusive comparison avoids losing a role update when the
            // database and sync cursor have the same one-second precision.
            ->when($since, fn ($query) => $query->where('updated_at', '>=', $since))
            ->get(['item_type', 'item_id']);
        foreach ($permissionChanges->groupBy('item_type') as $type => $shares) {
            $isNote = $type === 'note';
            $bucket = $isNote ? 'notes' : 'todos';
            $model = $isNote ? Note::class : Todo::class;
            $resource = $isNote ? NoteResource::class : TodoResource::class;
            $rowsByUuid = collect($changes[$bucket])->keyBy('uuid');
            foreach ($model::query()->whereIn('id', $shares->pluck('item_id'))->get() as $item) {
                $rowsByUuid[$item->uuid] = (new $resource($item))->resolve();
            }
            $changes[$bucket] = $rowsByUuid->values()->all();
        }

        return response()->json([
            'data' => [
                ...$changes,
                'deleted' => $deleted,
                'server_time' => now()->setTimezone('UTC')->format('Y-m-d\TH:i:s\Z'),
            ],
        ]);
    }

    /**
     * Idempotent push keyed on the client uuid. A row whose server-side
     * updated_at is newer than the client copy is reported as a conflict and
     * left untouched so the client can merge.
     */
    public function push(SyncPushRequest $request): JsonResponse
    {
        $accepted = [];
        $conflicts = [];
        $revoked = [];
        $readOnly = [];

        foreach (self::PUSH_ORDER as $bucket) {
            $meta = self::TYPES[$bucket];

            foreach ((array) $request->input($bucket, []) as $item) {
                $result = $this->upsertItem($meta, $item);

                if ($result['status'] === 'conflict') {
                    $conflicts[] = [
                        'type' => $meta['label'],
                        'uuid' => $item['uuid'],
                        'server' => $result['server'],
                    ];
                } elseif ($result['status'] === 'read_only') {
                    $readOnly[] = [
                        'type' => $meta['label'],
                        'uuid' => $item['uuid'],
                        'server' => $result['server'],
                    ];
                } elseif ($result['status'] === 'revoked') {
                    $revoked[] = ['type' => $meta['label'], 'uuid' => $item['uuid']];
                } else {
                    $accepted[] = ['type' => $meta['label'], 'uuid' => $item['uuid']];
                }
            }
        }

        foreach ((array) $request->input('deletes', []) as $delete) {
            $model = $this->modelForDeleteType($delete['type']);

            if ($model) {
                $row = $model::findByUuid($delete['uuid'], withTrashed: true);

                if ($row && ! $row->trashed()) {
                    if (in_array($model, [Note::class, Todo::class], true)
                        && (int) $row->user_id !== (int) $request->user()->id) {
                        $resource = $model === Note::class ? NoteResource::class : TodoResource::class;
                        $readOnly[] = [
                            'type' => $model === Note::class ? 'note' : 'todo',
                            'uuid' => $row->uuid,
                            'server' => (new $resource($row))->resolve(),
                        ];
                        continue;
                    }
                    $row->delete();
                }
            }

            // Unknown uuids are accepted too: deletes must be idempotent.
            $accepted[] = ['type' => strtolower(rtrim($delete['type'], 's')), 'uuid' => $delete['uuid']];
        }

        return response()->json([
            'data' => [
                'accepted' => $accepted,
                'conflicts' => $conflicts,
                'revoked' => $revoked,
                'read_only' => $readOnly,
                'server_time' => now()->setTimezone('UTC')->format('Y-m-d\TH:i:s\Z'),
            ],
        ]);
    }

    private function upsertItem(array $meta, array $item): array
    {
        $model = $meta['model'];

        if (! $this->referencesAvailable($meta['label'], $item)) {
            return ['status' => 'revoked'];
        }

        $existing = $model::findByUuid($item['uuid'], withTrashed: true);

        if ($existing) {
            // A collaborator may edit an active shared row, but cannot revive
            // an owner-deleted row through an offline upsert.
            if ($existing->trashed()
                && in_array($model, [Note::class, Todo::class], true)
                && (int) $existing->user_id !== (int) auth()->id()) {
                return [
                    'status' => 'read_only',
                    'server' => new $meta['resource']($existing)->resolve(),
                ];
            }

            if (in_array($model, [Note::class, Todo::class], true)
                && (int) $existing->user_id !== (int) auth()->id()) {
                $type = $model === Note::class ? 'note' : 'todo';
                $permission = ItemShare::query()
                    ->where('item_type', $type)
                    ->where('item_id', $existing->id)
                    ->where('shared_with_user_id', auth()->id())
                    ->whereNull('revoked_at')
                    ->value('permission');
                if ($permission !== 'editor') {
                    return [
                        'status' => 'read_only',
                        'server' => new $meta['resource']($existing)->resolve(),
                    ];
                }
            }

            $clientTime = Timestamp::utc('updated_at', $item['updated_at'] ?? null);

            if ($clientTime && $existing->updated_at && $existing->updated_at->greaterThan($clientTime)) {
                return [
                    'status' => 'conflict',
                    'server' => new $meta['resource']($existing)->resolve(),
                ];
            }

            $existing->fill($this->attributes($model, $item));

            if ($clientTime) {
                $existing->updated_at = $clientTime;
                $existing->exists = true;
            }

            $existing->forceFill(['synced_at' => now()])->save();

            if ($existing->trashed()) {
                $existing->restore();
            }

            return ['status' => 'accepted'];
        }

        // A UUID belonging to an account that revoked sharing must never be
        // recreated as a new row owned by the former collaborator.
        $existsOutsideAccess = $model::withoutGlobalScope(OwnedByUserScope::class)
            ->withTrashed()
            ->where('uuid', $item['uuid'])
            ->exists();
        if ($existsOutsideAccess) {
            return ['status' => 'revoked'];
        }

        $model::create([
            ...$this->attributes($model, $item),
            'user_id' => auth()->id(),
            'synced_at' => now(),
        ]);

        return ['status' => 'accepted'];
    }

    private function referencesAvailable(string $type, array $item): bool
    {
        $references = match ($type) {
            'link' => [
                ['type' => $item['source_type'], 'uuid' => $item['source_uuid']],
                ['type' => $item['target_type'], 'uuid' => $item['target_uuid']],
            ],
            'reminder' => [
                ['type' => $item['item_type'], 'uuid' => $item['item_uuid']],
            ],
            default => [],
        };

        foreach ($references as $reference) {
            if (ItemResolver::find($reference['type'], $reference['uuid']) === null) {
                return false;
            }
        }

        return true;
    }

    private function attributes(string $model, array $item): array
    {
        $attributes = array_intersect_key($item, array_flip((new $model)->getFillable()));

        unset($attributes['user_id']);

        return Timestamp::forModel($model, $attributes);
    }

    private function modelForDeleteType(string $type): ?string
    {
        return match (strtolower($type)) {
            'note', 'notes' => Note::class,
            'todo', 'todos' => Todo::class,
            'link', 'links' => Link::class,
            'reminder', 'reminders' => Reminder::class,
            default => null,
        };
    }
}
