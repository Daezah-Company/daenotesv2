<?php

namespace App\Http\Requests\Sync;

use App\Support\ItemResolver;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Validates a batch of offline changes.
 *
 * Links and reminders reference items by uuid, and a client may push the edge
 * before — or after — the items it points at, because the whole batch is one
 * atomic snapshot of the local database. So a uuid that appears anywhere in
 * this payload counts as an existing target even if the server has never seen
 * it yet; only genuinely unknown references are rejected.
 */
class SyncPushRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'notes' => ['sometimes', 'array'],
            'notes.*.uuid' => ['required', 'string', 'max:36'],
            'notes.*.group_name' => ['nullable', 'string', 'max:80'],
            'notes.*.updated_at' => ['sometimes', 'date'],

            'todos' => ['sometimes', 'array'],
            'todos.*.uuid' => ['required', 'string', 'max:36'],
            'todos.*.group_name' => ['nullable', 'string', 'max:80'],
            'todos.*.updated_at' => ['sometimes', 'date'],

            'links' => ['sometimes', 'array'],
            'links.*.uuid' => ['required', 'string', 'max:36'],
            'links.*.source_type' => ['required', 'in:note,todo'],
            'links.*.source_uuid' => ['required', 'string', 'max:36'],
            'links.*.target_type' => ['required', 'in:note,todo'],
            'links.*.target_uuid' => ['required', 'string', 'max:36'],
            'links.*.updated_at' => ['sometimes', 'date'],

            'reminders' => ['sometimes', 'array'],
            'reminders.*.uuid' => ['required', 'string', 'max:36'],
            'reminders.*.item_type' => ['required', 'in:note,todo'],
            'reminders.*.item_uuid' => ['required', 'string', 'max:36'],
            'reminders.*.updated_at' => ['sometimes', 'date'],

            'deletes' => ['sometimes', 'array'],
            'deletes.*.type' => ['required', 'in:note,todo,link,reminder,notes,todos,links,reminders'],
            'deletes.*.uuid' => ['required', 'string', 'max:36'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if ($validator->errors()->isNotEmpty()) {
                return;
            }

            $pushed = [
                'note' => array_column((array) $this->input('notes', []), 'uuid'),
                'todo' => array_column((array) $this->input('todos', []), 'uuid'),
            ];

            $references = $this->references();
            $unseen = ['note' => [], 'todo' => []];

            foreach ($references as $reference) {
                $type = $reference['type'];

                if (! in_array($reference['uuid'], $pushed[$type] ?? [], true)) {
                    $unseen[$type][] = $reference['uuid'];
                }
            }

            // One query per item type for the whole batch, never per reference.
            $known = [
                'note' => ItemResolver::knownUuids('note', $unseen['note']),
                'todo' => ItemResolver::knownUuids('todo', $unseen['todo']),
            ];
            $revoked = [
                'note' => ItemResolver::revokedUuids('note', $unseen['note'], (int) $this->user()->id),
                'todo' => ItemResolver::revokedUuids('todo', $unseen['todo'], (int) $this->user()->id),
            ];

            foreach ($references as $reference) {
                $type = $reference['type'];

                if (in_array($reference['uuid'], $pushed[$type] ?? [], true)
                    || isset($known[$type][$reference['uuid']])
                    || isset($revoked[$type][$reference['uuid']])) {
                    continue;
                }

                $validator->errors()->add(
                    $reference['path'],
                    "The {$type} {$reference['uuid']} does not exist.",
                );
            }
        });
    }

    /**
     * Every inter-item pointer in the payload, tagged with its field path.
     *
     * @return list<array{path: string, type: string, uuid: string}>
     */
    private function references(): array
    {
        $references = [];

        foreach ((array) $this->input('links', []) as $index => $link) {
            foreach (['source', 'target'] as $side) {
                $references[] = [
                    'path' => "links.{$index}.{$side}_uuid",
                    'type' => (string) ($link["{$side}_type"] ?? 'note'),
                    'uuid' => (string) ($link["{$side}_uuid"] ?? ''),
                ];
            }
        }

        foreach ((array) $this->input('reminders', []) as $index => $reminder) {
            $references[] = [
                'path' => "reminders.{$index}.item_uuid",
                'type' => (string) ($reminder['item_type'] ?? 'note'),
                'uuid' => (string) ($reminder['item_uuid'] ?? ''),
            ];
        }

        return $references;
    }
}
