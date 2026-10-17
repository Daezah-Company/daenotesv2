<?php

namespace App\Http\Resources;

use App\Http\Resources\Concerns\FormatsTimestamps;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TodoResource extends JsonResource
{
    use FormatsTimestamps;

    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'title' => $this->title,
            'notes' => $this->notes,
            'done' => (bool) $this->done,
            'done_at' => $this->ts($this->done_at),
            'priority' => $this->priority,
            'due_at' => $this->ts($this->due_at),
            'remind_at' => $this->ts($this->remind_at),
            'archived_at' => $this->ts($this->archived_at),
            'deleted_at' => $this->ts($this->deleted_at),
            'synced_at' => $this->ts($this->synced_at),
            'updated_at' => $this->ts($this->updated_at),
        ];
    }
}
