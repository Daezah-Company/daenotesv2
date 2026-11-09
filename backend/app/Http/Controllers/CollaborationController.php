<?php

namespace App\Http\Controllers;

use App\Models\ItemShare;
use App\Models\Link;
use App\Models\Note;
use App\Models\Reminder;
use App\Models\Todo;
use App\Models\Scopes\OwnedByUserScope;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CollaborationController extends Controller
{
    public function index(Request $request, string $type, string $uuid): JsonResponse
    {
        $item = $this->accessibleItem($type, $uuid);
        $shares = ItemShare::query()
            ->with('sharedWith:id,name,email')
            ->where('item_type', $type)
            ->where('item_id', $item->id)
            ->whereNull('revoked_at')
            ->get();
        $canManage = (int) $item->user_id === (int) $request->user()->id;
        $owner = $item->user()->first(['id', 'name', 'email']);

        return response()->json(['data' => [
            'owner' => $owner ? [
                'user_id' => $owner->id,
                'name' => $owner->name,
                'email' => $owner->email,
            ] : null,
            // Recipients only need to know who owns the item. The owner sees
            // the invite list; invitees must not receive other people's email.
            'collaborators' => $canManage ? $shares->map(fn (ItemShare $share) => [
                'user_id' => $share->shared_with_user_id,
                'name' => $share->sharedWith->name,
                'email' => $share->sharedWith->email,
                'permission' => $share->permission,
                'shared_at' => $share->created_at?->toISOString(),
            ])->values() : [],
            'my_permission' => $canManage ? 'owner' : $shares
                ->firstWhere('shared_with_user_id', $request->user()->id)?->permission,
            'can_manage' => $canManage,
        ]]);
    }

    public function store(Request $request, string $type, string $uuid): JsonResponse
    {
        $item = $this->accessibleItem($type, $uuid);
        $this->assertOwner($request, $item);
        $data = $request->validate([
            'email' => ['required', 'email', 'exists:users,email'],
            'permission' => ['sometimes', 'in:viewer,editor'],
        ]);
        $collaborator = $request->user()->newQuery()
            ->where('email', $data['email'])
            ->firstOrFail();

        if ($collaborator->is($request->user()) || (int) $collaborator->id === (int) $item->user_id) {
            throw ValidationException::withMessages([
                'email' => ['Akun ini sudah memiliki akses ke item tersebut.'],
            ]);
        }

        // The share table has no soft-delete scope; updateOrCreate reactivates
        // a previously revoked invitation without creating duplicate grants.
        $share = ItemShare::query()->updateOrCreate(
            [
                'item_type' => $type,
                'item_id' => $item->id,
                'shared_with_user_id' => $collaborator->id,
            ],
            [
                'owner_user_id' => $item->user_id,
                'permission' => $data['permission'] ?? 'editor',
                'revoked_at' => null,
            ],
        );

        return response()->json(['data' => [
            'user_id' => $collaborator->id,
            'name' => $collaborator->name,
            'email' => $collaborator->email,
            'shared_at' => $share->created_at?->toISOString(),
        ]], 201);
    }

    public function update(Request $request, string $type, string $uuid, int $userId): JsonResponse
    {
        $item = $this->accessibleItem($type, $uuid);
        $this->assertOwner($request, $item);
        $data = $request->validate(['permission' => ['required', 'in:viewer,editor']]);
        $share = ItemShare::query()
            ->where('item_type', $type)
            ->where('item_id', $item->id)
            ->where('shared_with_user_id', $userId)
            ->whereNull('revoked_at')
            ->firstOrFail();
        $share->forceFill(['permission' => $data['permission']])->save();

        return response()->json(['data' => [
            'user_id' => $userId,
            'permission' => $share->permission,
        ]]);
    }

    public function destroy(Request $request, string $type, string $uuid, int $userId): JsonResponse
    {
        $item = $this->accessibleItem($type, $uuid);
        $this->assertOwner($request, $item);
        $share = ItemShare::query()
            ->where('item_type', $type)
            ->where('item_id', $item->id)
            ->where('shared_with_user_id', $userId)
            ->whereNull('revoked_at')
            ->firstOrFail();
        DB::transaction(function () use ($share, $type, $uuid, $userId) {
            $share->forceFill(['revoked_at' => now()])->save();

            // Remove collaborator-owned references that would otherwise keep
            // exposing the revoked item through their graph or reminders.
            Link::withoutGlobalScope(OwnedByUserScope::class)
                ->where('user_id', $userId)
                ->where(function ($query) use ($type, $uuid) {
                    $query->where(fn ($side) => $side->where('source_type', $type)->where('source_uuid', $uuid))
                        ->orWhere(fn ($side) => $side->where('target_type', $type)->where('target_uuid', $uuid));
                })
                ->get()
                ->each(fn (Link $link) => $link->delete());
            Reminder::withoutGlobalScope(OwnedByUserScope::class)
                ->where('user_id', $userId)
                ->where('item_type', $type)
                ->where('item_uuid', $uuid)
                ->get()
                ->each(fn (Reminder $reminder) => $reminder->delete());
        });

        return response()->json(['data' => ['revoked' => true, 'user_id' => $userId]]);
    }

    private function accessibleItem(string $type, string $uuid): Note|Todo
    {
        $model = match ($type) {
            'note' => Note::class,
            'todo' => Todo::class,
            default => abort(404),
        };
        return $model::query()->where('uuid', $uuid)->firstOrFail();
    }

    private function assertOwner(Request $request, Note|Todo $item): void
    {
        abort_unless((int) $item->user_id === (int) $request->user()->id, 403);
    }
}
