<?php

namespace App\Http\Resources;

use App\Http\Resources\Concerns\FormatsTimestamps;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ReminderResource extends JsonResource
{
    use FormatsTimestamps;

    public function toArray(Request $request): array
    {
        return [
            'uuid' => $this->uuid,
            'item_type' => $this->item_type,
            'item_uuid' => $this->item_uuid,
            'title' => $this->title,
            'scheduled_at' => $this->ts($this->scheduled_at),
            'fired_at' => $this->ts($this->fired_at),
            'deleted_at' => $this->ts($this->deleted_at),
            'synced_at' => $this->ts($this->synced_at),
            'updated_at' => $this->ts($this->updated_at),
        ];
    }
}
