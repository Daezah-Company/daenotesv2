<?php

namespace App\Models\Scopes;

use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

class OwnedByUserScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        if ($user = auth()->user()) {
            $table = $model->getTable();
            $itemType = match ($table) {
                'notes' => 'note',
                'todos' => 'todo',
                default => null,
            };

            $builder->where(function (Builder $query) use ($table, $itemType, $user) {
                $query->where($table.'.user_id', $user->id);

                if ($itemType !== null) {
                    $query->orWhereExists(function (QueryBuilder $shares) use ($table, $itemType, $user) {
                        $shares->selectRaw('1')
                            ->from('item_shares')
                            ->where('item_shares.item_type', $itemType)
                            ->whereColumn('item_shares.item_id', $table.'.id')
                            ->where('item_shares.shared_with_user_id', $user->id)
                            ->whereNull('item_shares.revoked_at');
                    });
                }
            });

            if ($itemType !== null) {
                $builder->addSelect([
                    'shared_permission' => \Illuminate\Support\Facades\DB::table('item_shares')
                        ->select('permission')
                        ->where('item_shares.item_type', $itemType)
                        ->whereColumn('item_shares.item_id', $table.'.id')
                        ->where('item_shares.shared_with_user_id', $user->id)
                        ->whereNull('item_shares.revoked_at')
                        ->limit(1),
                ]);
            }
        }
    }
}
