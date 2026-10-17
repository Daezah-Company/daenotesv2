<?php

namespace Tests\Feature;

use App\Models\Link;
use App\Models\Note;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class GraphTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        Sanctum::actingAs($this->user);
    }

    public function test_graph_depth_1_from_root_returns_direct_neighbours_only(): void
    {
        $root = Note::factory()->for($this->user)->create(['title' => 'root']);
        $child = Todo::factory()->for($this->user)->create(['title' => 'child']);
        $grandchild = Note::factory()->for($this->user)->create(['title' => 'grandchild']);

        Link::factory()->for($this->user)->between($root, $child)->create();
        Link::factory()->for($this->user)->between($child, $grandchild)->create();

        $response = $this->getJson("/api/graph?depth=1&root={$root->uuid}")
            ->assertOk()
            ->assertJsonStructure(['data' => ['nodes', 'edges']]);

        $titles = collect($response->json('data.nodes'))->pluck('title');
        $this->assertTrue($titles->contains('root'));
        $this->assertTrue($titles->contains('child'));
        $this->assertFalse($titles->contains('grandchild'));
        $this->assertCount(1, $response->json('data.edges'));
    }

    public function test_graph_depth_2_reaches_second_hop(): void
    {
        $root = Note::factory()->for($this->user)->create(['title' => 'root']);
        $child = Todo::factory()->for($this->user)->create(['title' => 'child']);
        $grandchild = Note::factory()->for($this->user)->create(['title' => 'grandchild']);
        $far = Note::factory()->for($this->user)->create(['title' => 'far-away']);

        Link::factory()->for($this->user)->between($root, $child)->create();
        Link::factory()->for($this->user)->between($child, $grandchild)->create();
        Link::factory()->for($this->user)->between($grandchild, $far)->create();

        $response = $this->getJson("/api/graph?depth=2&root={$root->uuid}")->assertOk();

        $titles = collect($response->json('data.nodes'))->pluck('title');
        $this->assertTrue($titles->contains('grandchild'));
        $this->assertFalse($titles->contains('far-away'));
        $this->assertCount(2, $response->json('data.edges'));
    }

    public function test_graph_addresses_every_node_and_edge_by_uuid(): void
    {
        $note = Note::factory()->for($this->user)->create(['uuid' => 'graph-note-uuid']);
        $todo = Todo::factory()->for($this->user)->create(['uuid' => 'graph-todo-uuid']);

        Link::factory()->for($this->user)->between($note, $todo)->create(['uuid' => 'graph-edge-uuid']);

        $response = $this->getJson('/api/graph')->assertOk();

        $keys = collect($response->json('data.nodes'))->pluck('uuid');
        $this->assertTrue($keys->contains('graph-note-uuid'));
        $this->assertTrue($keys->contains('graph-todo-uuid'));

        $this->assertSame([
            'uuid' => 'graph-edge-uuid',
            'source_type' => 'note',
            'source_uuid' => 'graph-note-uuid',
            'target_type' => 'todo',
            'target_uuid' => 'graph-todo-uuid',
            'label' => null,
        ], $response->json('data.edges.0'));

        // No bigint leaks: nodes and edges carry uuid only.
        $this->assertArrayNotHasKey('id', $response->json('data.nodes.0'));
        $this->assertArrayNotHasKey('source_id', $response->json('data.edges.0'));
    }

    public function test_graph_returns_edges_for_items_linked_by_uuid_through_the_api(): void
    {
        // Regression: the whole flow the offline client performs — create two
        // items with client uuids, link them by uuid, then read the graph.
        $this->postJson('/api/notes', [
            'uuid' => 'local-note-1', 'title' => 'Local note', 'body' => 'written offline',
        ])->assertCreated();
        $this->postJson('/api/todos', [
            'uuid' => 'local-todo-1', 'title' => 'Local todo', 'priority' => 'normal',
        ])->assertCreated();

        $this->postJson('/api/links', [
            'uuid' => 'local-link-1',
            'source_type' => 'note', 'source_uuid' => 'local-note-1',
            'target_type' => 'todo', 'target_uuid' => 'local-todo-1',
            'label' => 'benang',
        ])->assertCreated();

        $response = $this->getJson('/api/graph?depth=2&root=local-note-1')->assertOk();

        $this->assertCount(2, $response->json('data.nodes'));
        $this->assertSame('local-note-1', $response->json('data.edges.0.source_uuid'));
        $this->assertSame('local-todo-1', $response->json('data.edges.0.target_uuid'));
        $this->assertSame('benang', $response->json('data.edges.0.label'));
        $this->assertSame(
            ['local-link-1'],
            collect($response->json('data.edges'))->pluck('uuid')->all(),
        );
    }

    public function test_graph_types_filter_restricts_node_kinds(): void
    {
        $root = Note::factory()->for($this->user)->create();
        $child = Todo::factory()->for($this->user)->create();
        Link::factory()->for($this->user)->between($root, $child)->create();

        $response = $this->getJson("/api/graph?depth=1&root={$root->uuid}&types=note")->assertOk();

        $types = collect($response->json('data.nodes'))->pluck('type')->unique()->all();
        $this->assertSame(['note'], array_values($types));
        $this->assertCount(0, $response->json('data.edges'));
    }

    public function test_full_graph_without_root_and_query_count_stays_flat(): void
    {
        $nodes = Note::factory()->for($this->user)->count(12)->create();

        foreach ($nodes as $i => $node) {
            Link::factory()->for($this->user)->between($node, $nodes[($i + 1) % 12])->create();
        }

        $small = $this->graphQueryCount();

        $this->assertSame(12, $small['nodes']);
        $this->assertSame(12, $small['edges']);

        // one links query + one notes query (+ the auth bootstrap); never one per node.
        $this->assertLessThanOrEqual(8, $small['queries'], 'graph must not run per-node queries');

        // Growing the graph must not grow the query count: proof of no N+1.
        $extra = Note::factory()->for($this->user)->count(12)->create();

        foreach ($extra as $i => $node) {
            Link::factory()->for($this->user)->between($node, $extra[($i + 1) % 12])->create();
        }

        $large = $this->graphQueryCount();

        $this->assertSame(24, $large['nodes']);
        $this->assertSame(24, $large['edges']);
        $this->assertSame($small['queries'], $large['queries'], 'graph query count grew with the node count');
    }

    public function test_depth_graph_from_root_batches_queries_per_level(): void
    {
        $root = Note::factory()->for($this->user)->create();
        $children = Todo::factory()->for($this->user)->count(8)->create();
        $grandchildren = Note::factory()->for($this->user)->count(8)->create();

        foreach ($children as $i => $child) {
            Link::factory()->for($this->user)->between($root, $child)->create();
            Link::factory()->for($this->user)->between($child, $grandchildren[$i])->create();
        }

        $result = $this->graphQueryCount("/api/graph?depth=2&root={$root->uuid}");

        // level 1: 1 links + 1 todos; level 2: 1 links + 1 notes = 4, plus auth/root lookup.
        $this->assertSame(17, $result['nodes']);
        $this->assertSame(16, $result['edges']);
        $this->assertLessThanOrEqual(10, $result['queries']);
    }

    public function test_soft_deleted_items_disappear_from_graph(): void
    {
        $a = Note::factory()->for($this->user)->create();
        $b = Note::factory()->for($this->user)->create();
        Link::factory()->for($this->user)->between($a, $b)->create();

        $b->delete();

        $response = $this->getJson('/api/graph')->assertOk();
        $this->assertCount(0, $response->json('data.nodes'));
        $this->assertCount(0, $response->json('data.edges'));
    }

    /**
     * Hit the graph endpoint while recording every query it runs.
     *
     * @return array{nodes: int, edges: int, queries: int}
     */
    private function graphQueryCount(string $url = '/api/graph?depth=2'): array
    {
        DB::flushQueryLog();
        DB::enableQueryLog();

        $response = $this->getJson($url)->assertOk();

        $queries = count(DB::getQueryLog());
        DB::disableQueryLog();

        return [
            'nodes' => count($response->json('data.nodes')),
            'edges' => count($response->json('data.edges')),
            'queries' => $queries,
        ];
    }
}
