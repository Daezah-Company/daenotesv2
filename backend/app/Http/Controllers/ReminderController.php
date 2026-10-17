<?php

namespace App\Http\Controllers;

use App\Http\Requests\Reminders\StoreReminderRequest;
use App\Http\Resources\ReminderResource;
use App\Models\Reminder;
use App\Support\Timestamp;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class ReminderController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $query = Reminder::query();

        if ($request->boolean('upcoming')) {
            $query->whereNull('fired_at')->where('scheduled_at', '>', now());
        }

        if ($request->boolean('fired')) {
            $query->whereNotNull('fired_at');
        }

        return ReminderResource::collection($query->orderBy('scheduled_at')->get());
    }

    public function store(StoreReminderRequest $request): JsonResponse
    {
        $data = Timestamp::forModel(Reminder::class, $request->validated());

        if ($existing = Reminder::findByUuid($data['uuid'], withTrashed: true)) {
            if ($existing->trashed()) {
                $existing->fill($data)->restore();
                $existing->forceFill(['synced_at' => now()])->save();

                return response()->json(['data' => new ReminderResource($existing)], 200);
            }

            return response()->json([
                'message' => 'The uuid has already been used.',
                'errors' => ['uuid' => ['The reminder uuid already exists.']],
            ], 422);
        }

        $reminder = Reminder::create([...$data, 'user_id' => $request->user()->id, 'synced_at' => now()]);

        return response()->json(['data' => new ReminderResource($reminder)], 201);
    }

    public function fire(string $uuid): ReminderResource
    {
        $reminder = $this->findOwned(Reminder::class, $uuid);
        $reminder->forceFill(['fired_at' => now(), 'synced_at' => now()])->save();

        return new ReminderResource($reminder->fresh());
    }
}
