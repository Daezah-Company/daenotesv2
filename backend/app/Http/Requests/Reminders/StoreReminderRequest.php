<?php

namespace App\Http\Requests\Reminders;

use App\Support\ItemResolver;
use Illuminate\Foundation\Http\FormRequest;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * A reminder points at its item by uuid; the item must belong to the caller.
 * Unknown or foreign uuid gives 404, matching the rest of the API.
 */
class StoreReminderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'uuid' => ['required', 'string', 'max:36'],
            'item_type' => ['required', 'in:note,todo'],
            'item_uuid' => ['required', 'string', 'max:36'],
            'title' => ['required', 'string', 'max:255'],
            'scheduled_at' => ['required', 'date'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if ($validator->errors()->isNotEmpty()) {
                return;
            }

            $type = (string) $this->input('item_type');

            if (! ItemResolver::find($type, (string) $this->input('item_uuid'))) {
                throw new HttpException(404, "The {$type} does not exist.");
            }
        });
    }
}
