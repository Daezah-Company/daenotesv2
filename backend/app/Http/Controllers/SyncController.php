<?php

namespace App\Http\Controllers;

use App\Http\Requests\Sync\SyncPushRequest;
use App\Http\Resources\LinkResource;
use App\Http\Resources\NoteResource;
use App\Http\Resources\ReminderResource;
use App\Http\Resources\TodoResource;
use App\Models\Link;
use App\Models\Note;
use App\Models\Reminder;
use App\Models\Todo;
use App\Support\Timestamp;
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
                'server_time' => now()->setTimezone('UTC')->format('Y-m-d\TH:i:s\Z'),
            ],
        ]);
    }

    private function upsertItem(array $meta, array $item): array
    {
        $model = $meta['model'];
        $existing = $model::findByUuid($item['uuid'], withTrashed: true);

        if ($existing) {
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

        $model::create([
            ...$this->attributes($model, $item),
            'user_id' => auth()->id(),
            'synced_at' => now(),
        ]);

        return ['status' => 'accepted'];
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
