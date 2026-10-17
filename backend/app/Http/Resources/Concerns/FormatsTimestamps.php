<?php

namespace App\Http\Resources\Concerns;

use Carbon\Carbon;
use DateTimeInterface;

/**
 * Single point of truth for how every resource serialises an instant.
 *
 * The database stores UTC, so responses must say so explicitly: every datetime
 * is rendered as a UTC ISO8601 string terminated with the "Z" designator. A bare
 * local wall-clock (or a "+00:00" that a sloppy client might drop) can never be
 * misread, and the value round-trips back to the exact stored instant.
 */
trait FormatsTimestamps
{
    protected function ts(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }

        if ($value instanceof DateTimeInterface) {
            return Carbon::instance($value)->setTimezone('UTC')->format('Y-m-d\TH:i:s\Z');
        }

        return is_scalar($value) ? (string) $value : null;
    }
}
