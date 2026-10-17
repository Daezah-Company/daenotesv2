<?php

namespace App\Http\Controllers;

use App\Http\Requests\Todos\StoreTodoRequest;
use App\Http\Requests\Todos\UpdateTodoRequest;
use App\Http\Resources\TodoResource;
use App\Models\Todo;
use App\Support\Timestamp;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class TodoController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $query = Todo::query();

        if ($search = $request->string('q')->trim()->value()) {
            $query->where(function ($q) use ($search) {
                $q->where('title', 'like', "%{$search}%")
                    ->orWhere('notes', 'like', "%{$search}%");
            });
        }

        if ($request->has('done')) {
            $request->boolean('done')
                ? $query->where('done', true)
                : $query->where('done', false);
        }

        match ($request->input('due')) {
            'today' => $query->whereDate('due_at', today()),
            'overdue' => $query->where('done', false)
                ->whereNotNull('due_at')
                ->whereDate('due_at', '<', today()),
            'week' => $query->whereBetween('due_at', [now(), now()->addWeek()]),
            'any' => $query->whereNotNull('due_at'),
            default => null,
        };

        if ($since = $request->input('updated_since')) {
            $query->withTrashed()->where('updated_at', '>', Timestamp::parse('updated_since', $since));
        }

        return TodoResource::collection(
            $query->orderByDesc('updated_at')->paginate(min(max((int) $request->input('per_page', 25), 1), 100))
        );
    }

    public function store(StoreTodoRequest $request): JsonResponse
    {
        $data = Timestamp::forModel(Todo::class, $request->validated());

        if ($existing = Todo::findByUuid($data['uuid'], withTrashed: true)) {
            if ($existing->trashed()) {
                $existing->fill($data)->restore();
                $existing->forceFill(['synced_at' => now()])->save();

                return response()->json(['data' => new TodoResource($existing)], 200);
            }

            return response()->json([
                'message' => 'The uuid has already been used.',
                'errors' => ['uuid' => ['The todo uuid already exists.']],
            ], 422);
        }

        $todo = Todo::create([...$data, 'user_id' => $request->user()->id, 'synced_at' => now()]);

        return response()->json(['data' => new TodoResource($todo)], 201);
    }

    public function update(UpdateTodoRequest $request, string $uuid): TodoResource
    {
        $todo = $this->findOwned(Todo::class, $uuid);
        $data = Timestamp::forModel(Todo::class, $request->validated());

        if (array_key_exists('done', $data)) {
            $data['done_at'] = $data['done'] ? ($todo->done_at ?? now()) : null;
        }

        $todo->fill($data)->forceFill(['synced_at' => now()])->save();

        return new TodoResource($todo->fresh());
    }

    public function toggle(string $uuid): TodoResource
    {
        $todo = $this->findOwned(Todo::class, $uuid);
        $done = ! $todo->done;

        $todo->forceFill([
            'done' => $done,
            'done_at' => $done ? now() : null,
            'synced_at' => now(),
        ])->save();

        return new TodoResource($todo->fresh());
    }

    public function destroy(string $uuid): JsonResponse
    {
        $todo = $this->findOwned(Todo::class, $uuid);
        $todo->delete();

        return response()->json([
            'data' => ['uuid' => $uuid, 'deleted' => true],
        ]);
    }
}
