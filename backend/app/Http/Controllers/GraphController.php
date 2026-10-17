<?php

namespace App\Http\Controllers;

use App\Models\Link;
use App\Models\Note;
use App\Models\Todo;
use App\Support\ItemResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class GraphController extends Controller
{
    /**
     * Returns {nodes:[], edges:[]} for the user's link graph.
     *
     * Nodes and edges are identified by client uuid only: the bigint ids are
     * internal and never leave the server, so an offline client can highlight
     * a thread between two items it has not synced yet.
     *
     * depth=1|2 expands hops from an optional `root` uuid (note or todo uuid).
     * Without a root the full graph is returned. Each level costs one links
     * query plus at most two item queries (one per node type), whatever the
     * number of nodes — so the query count stays flat as the graph grows.
     */
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'depth' => ['sometimes', 'in:1,2'],
            'types' => ['sometimes', 'string'],
            'root' => ['sometimes', 'string', 'max:36'],
        ]);

        $depth = (int) $request->input('depth', 1);
        $types = array_values(array_intersect(
            array_map('trim', explode(',', (string) $request->input('types', 'note,todo'))),
            ['note', 'todo']
        )) ?: ['note', 'todo'];

        $root = null;

        if ($rootUuid = $request->input('root')) {
            $root = $this->resolveNode($rootUuid);
        }

        $nodes = [];   // "type:uuid" => node payload
        $edges = [];   // link uuid => edge payload
        $visited = [];

        if ($root) {
            $nodes[$this->key($root)] = $this->nodePayload($root);
            $visited[$this->key($root)] = true;

            $frontier = [$root];

            for ($level = 0; $level < $depth; $level++) {
                if ($frontier === []) {
                    break;
                }

                $links = $this->linksTouching($frontier);

                foreach ($links as $link) {
                    $edges[$link->uuid] = $this->edgePayload($link);
                }

                $frontier = $this->nextFrontier($links, $visited, $types, $nodes);
            }

            // Drop edges that end on nodes filtered out or beyond the depth.
            $edges = array_filter(
                $edges,
                fn ($edge) => isset($nodes["{$edge['source_type']}:{$edge['source_uuid']}"])
                    && isset($nodes["{$edge['target_type']}:{$edge['target_uuid']}"])
            );
        } else {
            $links = Link::query()->orderBy('id')->get();

            $uuidsByType = ['note' => [], 'todo' => []];

            foreach ($links as $link) {
                $edges[$link->uuid] = $this->edgePayload($link);
                $uuidsByType[$link->source_type][] = $link->source_uuid;
                $uuidsByType[$link->target_type][] = $link->target_uuid;
            }

            foreach ($uuidsByType as $type => $uuids) {
                foreach (ItemResolver::loadNodes($type, $uuids) as $node) {
                    $nodes[$this->key($node)] = $this->nodePayload($node);
                }
            }

            $nodes = array_filter($nodes, fn ($node) => in_array($node['type'], $types, true));

            $edges = array_filter(
                $edges,
                fn ($edge) => isset($nodes["{$edge['source_type']}:{$edge['source_uuid']}"])
                    && isset($nodes["{$edge['target_type']}:{$edge['target_uuid']}"])
            );
            $anchors = [];

            foreach ($edges as $edge) {
                $anchors["{$edge['source_type']}:{$edge['source_uuid']}"] = true;
                $anchors["{$edge['target_type']}:{$edge['target_uuid']}"] = true;
            }

            $nodes = array_filter($nodes, fn ($node, $key) => isset($anchors[$key]), ARRAY_FILTER_USE_BOTH);
        }

        return response()->json([
            'data' => [
                'nodes' => array_values($nodes),
                'edges' => array_values($edges),
            ],
        ]);
    }

    private function resolveNode(string $uuid): ?object
    {
        foreach ([Note::class, Todo::class] as $class) {
            if ($node = $class::query()->where('uuid', $uuid)->first()) {
                return $node;
            }
        }

        abort(404);
    }

    /** One batched query for all links touching any node of the frontier. */
    private function linksTouching(array $frontier)
    {
        $uuidsByType = ['note' => [], 'todo' => []];

        foreach ($frontier as $node) {
            $uuidsByType[$this->type($node)][] = $node->uuid;
        }

        return Link::query()->where(function ($query) use ($uuidsByType) {
            foreach ($uuidsByType as $type => $uuids) {
                if ($uuids === []) {
                    continue;
                }

                $query->orWhere(function ($side) use ($type, $uuids) {
                    $side->where('source_type', $type)->whereIn('source_uuid', $uuids)
                        ->orWhere(function ($target) use ($type, $uuids) {
                            $target->where('target_type', $type)->whereIn('target_uuid', $uuids);
                        });
                });
            }
        })->get();
    }

    /** Batch-loads the newly discovered neighbours; max 2 queries. */
    private function nextFrontier($links, array &$visited, array $types, array &$nodes): array
    {
        $uuidsByType = ['note' => [], 'todo' => []];

        foreach ($links as $link) {
            foreach ([['source', $link->source_type, $link->source_uuid], ['target', $link->target_type, $link->target_uuid]] as [, $type, $uuid]) {
                $key = "{$type}:{$uuid}";

                if (! isset($visited[$key]) && in_array($type, $types, true)) {
                    $visited[$key] = true;
                    $uuidsByType[$type][] = $uuid;
                }
            }
        }

        $next = [];

        foreach ($uuidsByType as $type => $uuids) {
            foreach (ItemResolver::loadNodes($type, $uuids) as $node) {
                $nodes[$this->key($node)] = $this->nodePayload($node);
                $next[] = $node;
            }
        }

        return $next;
    }

    private function key(object $node): string
    {
        return "{$this->type($node)}:{$node->uuid}";
    }

    private function type(object $node): string
    {
        return $node instanceof Todo ? 'todo' : 'note';
    }

    private function nodePayload($node): array
    {
        return [
            'type' => $this->type($node),
            'uuid' => $node->uuid,
            'title' => $node->title,
        ];
    }

    private function edgePayload(Link $link): array
    {
        return [
            'uuid' => $link->uuid,
            'source_type' => $link->source_type,
            'source_uuid' => $link->source_uuid,
            'target_type' => $link->target_type,
            'target_uuid' => $link->target_uuid,
            'label' => $link->label,
        ];
    }
}
