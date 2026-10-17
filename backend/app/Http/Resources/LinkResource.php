<?php

namespace App\Http\Resources;

use App\Http\Resources\Concerns\FormatsTimestamps;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class LinkResource extends JsonResource
{
    use FormatsTimestamps;

    public function toArray(Request $request): array
    {
        return [
            'uuid' => $this->uuid,
            'source_type' => $this->source_type,
            'source_uuid' => $this->source_uuid,
            'target_type' => $this->target_type,
            'target_uuid' => $this->target_uuid,
            'label' => $this->label,
            'deleted_at' => $this->ts($this->deleted_at),
            'synced_at' => $this->ts($this->synced_at),
            'created_at' => $this->ts($this->created_at),
            'updated_at' => $this->ts($this->updated_at),
        ];
    }
}
