<?php

namespace App\Http\Resources;

use App\Http\Resources\Concerns\FormatsTimestamps;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class NoteResource extends JsonResource
{
    use FormatsTimestamps;

    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'owner_user_id' => (int) $this->user_id,
            'access_level' => (int) $this->user_id === (int) $request->user()?->id
                ? 'owner'
                : ($this->shared_permission ?? 'viewer'),
            'title' => $this->title,
            'group_name' => $this->group_name,
            'body' => $this->body,
            'color' => $this->color,
            'pinned' => (bool) $this->pinned,
            'archived_at' => $this->ts($this->archived_at),
            'deleted_at' => $this->ts($this->deleted_at),
            'synced_at' => $this->ts($this->synced_at),
            'updated_at' => $this->ts($this->updated_at),
        ];
    }
}
