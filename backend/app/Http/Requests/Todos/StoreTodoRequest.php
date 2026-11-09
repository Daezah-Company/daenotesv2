<?php

namespace App\Http\Requests\Todos;

use Illuminate\Foundation\Http\FormRequest;

class StoreTodoRequest extends FormRequest
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
            'group_name' => ['nullable', 'string', 'max:80'],
            'notes' => ['nullable', 'string'],
            'priority' => ['sometimes', 'in:low,normal,high'],
            'due_at' => ['nullable', 'date'],
            'remind_at' => ['nullable', 'date'],
        ];
    }
}
