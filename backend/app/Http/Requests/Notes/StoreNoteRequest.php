<?php

namespace App\Http\Requests\Notes;

use Illuminate\Foundation\Http\FormRequest;

class StoreNoteRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'uuid' => ['required', 'string', 'max:36'],
            'title' => ['required', 'string', 'max:255'],
            'body' => ['required', 'string'],
            'color' => ['nullable', 'string', 'max:32'],
            'pinned' => ['sometimes', 'boolean'],
        ];
    }
}
