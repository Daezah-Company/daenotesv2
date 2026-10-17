<?php

namespace App\Http\Controllers;

use App\Http\Requests\Links\StoreLinkRequest;
use App\Http\Resources\LinkResource;
use App\Models\Link;
use App\Support\Timestamp;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class LinkController extends Controller
{
    /**
     * Neighbours one hop away from a given item, addressed by uuid.
     *
     * `item_uuid` is the documented name; `item_id` is accepted as an alias for
     * clients that still spell the filter that way, but it carries a uuid too —
     * internal bigint ids are never part of this API.
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $request->validate([
            'item_type' => ['required', 'in:note,todo'],
            'item_uuid' => ['required_without:item_id', 'string', 'max:36'],
            'item_id' => ['required_without:item_uuid', 'string', 'max:36'],
        ]);

        $type = $request->input('item_type');
        $uuid = (string) ($request->input('item_uuid') ?? $request->input('item_id'));

        $links = Link::query()
            ->where(function ($q) use ($type, $uuid) {
                $q->where(fn ($s) => $s->where('source_type', $type)->where('source_uuid', $uuid))
                    ->orWhere(fn ($t) => $t->where('target_type', $type)->where('target_uuid', $uuid));
            })
            ->orderByDesc('created_at')
            ->get();

        return LinkResource::collection($links);
    }

    public function store(StoreLinkRequest $request): JsonResponse
    {
        $data = Timestamp::forModel(Link::class, $request->validated());
        $userId = $request->user()->id;

        // Idempotency on uuid: a trashed row is restored instead of duplicated.
        if ($byUuid = Link::findByUuid($data['uuid'], withTrashed: true)) {
            if ($byUuid->trashed()) {
                $clash = Link::query()
                    ->where('id', '!=', $byUuid->id)
                    ->where('source_type', $data['source_type'])->where('source_uuid', $data['source_uuid'])
                    ->where('target_type', $data['target_type'])->where('target_uuid', $data['target_uuid'])
                    ->exists();

                if ($clash) {
                    return response()->json([
                        'message' => 'These items are already linked.',
                        'errors' => ['source_uuid' => ['A live link between these items already exists.']],
                    ], 422);
                }

                $byUuid->fill($data)->restore();
                $byUuid->forceFill(['synced_at' => now()])->save();

                return response()->json(['data' => new LinkResource($byUuid->fresh())], 200);
            }

            return response()->json([
                'message' => 'The uuid has already been used.',
                'errors' => ['uuid' => ['The link uuid already exists.']],
            ], 422);
        }

        // UNIQUE(user_id, source_uuid, target_uuid): reject a live duplicate,
        // revive a soft-deleted one so the index never blocks relinking — the
        // index does not carry deleted_at, so a trashed row must be reused.
        $pair = Link::withTrashed()
            ->where('source_type', $data['source_type'])
            ->where('source_uuid', $data['source_uuid'])
            ->where('target_type', $data['target_type'])
            ->where('target_uuid', $data['target_uuid'])
            ->first();

        if ($pair) {
            if (! $pair->trashed()) {
                return response()->json([
                    'message' => 'These items are already linked.',
                    'errors' => ['source_uuid' => ['A link between these items already exists.']],
                ], 422);
            }

            $pair->fill($data)->restore();
            $pair->forceFill(['synced_at' => now()])->save();

            return response()->json(['data' => new LinkResource($pair->fresh())], 200);
        }

        $link = Link::create([...$data, 'user_id' => $userId, 'synced_at' => now()]);

        return response()->json(['data' => new LinkResource($link)], 201);
    }

    public function destroy(string $uuid): JsonResponse
    {
        $link = $this->findOwned(Link::class, $uuid);
        $link->delete();

        return response()->json([
            'data' => ['uuid' => $uuid, 'deleted' => true],
        ]);
    }
}
