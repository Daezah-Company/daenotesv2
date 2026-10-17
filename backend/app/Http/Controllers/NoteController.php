<?php

namespace App\Http\Controllers;

use App\Http\Requests\Notes\StoreNoteRequest;
use App\Http\Requests\Notes\UpdateNoteRequest;
use App\Http\Resources\NoteResource;
use App\Models\Note;
use App\Support\Timestamp;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class NoteController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $query = Note::query();

        if ($search = $request->string('q')->trim()->value()) {
            $query->where(function ($q) use ($search) {
                $q->where('title', 'like', "%{$search}%")
                    ->orWhere('body', 'like', "%{$search}%");
            });
        }

        if ($request->has('archived')) {
            $request->boolean('archived')
                ? $query->whereNotNull('archived_at')
                : $query->whereNull('archived_at');
        }

        // Per contract: updated_since also returns soft-deleted rows so offline
        // clients can purge items deleted on the server.
        if ($since = $request->input('updated_since')) {
            $query->withTrashed()->where('updated_at', '>', Timestamp::parse('updated_since', $since));
        }

        return NoteResource::collection(
            $this->applySort($query, $request->input('sort'))
                ->paginate($this->perPage($request))
        );
    }

    public function store(StoreNoteRequest $request): JsonResponse
    {
        $data = Timestamp::forModel(Note::class, $request->validated());

        if ($existing = Note::findByUuid($data['uuid'], withTrashed: true)) {
            if ($existing->trashed()) {
                $existing->fill($data)->restore();
                $existing->forceFill(['synced_at' => now()])->save();

                return response()->json(['data' => new NoteResource($existing)], 200);
            }

            return response()->json([
                'message' => 'The uuid has already been used.',
                'errors' => ['uuid' => ['The note uuid already exists.']],
            ], 422);
        }

        $note = Note::create([...$data, 'user_id' => $request->user()->id, 'synced_at' => now()]);

        return response()->json(['data' => new NoteResource($note)], 201);
    }

    public function show(string $uuid): NoteResource
    {
        return new NoteResource($this->findOwned(Note::class, $uuid));
    }

    public function update(UpdateNoteRequest $request, string $uuid): NoteResource
    {
        $note = $this->findOwned(Note::class, $uuid);
        $note->fill(Timestamp::forModel(Note::class, $request->validated()))
            ->forceFill(['synced_at' => now()])->save();

        return new NoteResource($note->fresh());
    }

    public function destroy(string $uuid): JsonResponse
    {
        $note = $this->findOwned(Note::class, $uuid);
        $note->delete();

        return response()->json([
            'data' => ['uuid' => $uuid, 'deleted' => true],
        ]);
    }

    public function archive(string $uuid): NoteResource
    {
        $note = $this->findOwned(Note::class, $uuid);
        $note->forceFill(['archived_at' => now()])->save();

        return new NoteResource($note->fresh());
    }

    public function restore(string $uuid): NoteResource
    {
        $note = $this->findOwned(Note::class, $uuid, withTrashed: true);
        $note->forceFill(['archived_at' => null])->save();

        if ($note->trashed()) {
            $note->restore();
        }

        return new NoteResource($note->fresh());
    }

    private function applySort($query, ?string $sort)
    {
        $allowed = ['updated_at', 'title', 'pinned'];

        foreach (explode(',', (string) $sort) as $clause) {
            $clause = trim($clause);
            $direction = 'asc';

            if (str_starts_with($clause, '-')) {
                $direction = 'desc';
                $clause = substr($clause, 1);
            }

            if (in_array($clause, $allowed, true)) {
                $query->orderBy($clause, $direction);
            }
        }

        return $query->orderByDesc('updated_at');
    }

    private function perPage(Request $request): int
    {
        return min(max((int) $request->input('per_page', 25), 1), 100);
    }
}
