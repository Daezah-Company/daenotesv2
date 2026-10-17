<?php

namespace App\Http\Requests\Links;

use App\Support\ItemResolver;
use Illuminate\Foundation\Http\FormRequest;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Validates an edge expressed entirely in client uuids.
 *
 * Both ends must resolve to a row owned by the caller. An unknown or foreign
 * uuid aborts with 404 — the same answer every other endpoint gives, because
 * the OwnedByUser scope never lets a foreign row be found, so existence is
 * never leaked through a 403.
 */
class StoreLinkRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'uuid' => ['required', 'string', 'max:36'],
            'source_type' => ['required', 'in:note,todo'],
            'source_uuid' => ['required', 'string', 'max:36'],
            'target_type' => ['required', 'in:note,todo'],
            'target_uuid' => ['required', 'string', 'max:36'],
            'label' => ['nullable', 'string', 'max:255'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if ($validator->errors()->isNotEmpty()) {
                return;
            }

            if ($this->input('source_type') === $this->input('target_type')
                && $this->input('source_uuid') === $this->input('target_uuid')) {
                $validator->errors()->add('target_uuid', 'An item cannot be linked to itself.');

                return;
            }

            foreach (['source', 'target'] as $side) {
                $type = (string) $this->input("{$side}_type");
                $uuid = (string) $this->input("{$side}_uuid");

                if (! ItemResolver::find($type, $uuid)) {
                    throw new HttpException(404, "The {$type} {$uuid} does not exist.");
                }
            }
        });
    }
}
