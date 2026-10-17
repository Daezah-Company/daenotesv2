<?php

namespace App\Support;

use Carbon\Carbon;
use DateTimeInterface;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Validation\ValidationException;

final class Timestamp
{
    /**
     * Cast names whose underlying column holds an instant and therefore has to
     * be normalised on the way in. Anything else is left untouched.
     */
    private const DATE_CASTS = ['datetime', 'date', 'immutable_datetime', 'immutable_date', 'date_with_time'];

    /**
     * Parse an ISO8601 query value into a UTC instant.
     *
     * Browsers and HTTP clients percent-encode the timezone offset, but some send
     * "+00:00" which PHP's query parser decodes back into a space. Kept as a
     * thin alias of self::utc() so query filters share the write-path semantics.
     */
    public static function parse(string $field, ?string $value): ?Carbon
    {
        return self::utc($field, $value);
    }

    /**
     * Turn any wire value into a UTC Carbon, or null when it is absent.
     *
     * Accepts a trailing "Z", numeric offsets such as "+07:00" (or the percent-
     * decoded " 07:00"), and naive local strings. Eloquent formats a datetime it
     * is handed using the value's OWN timezone, so a raw "+07:00" string — even a
     * "+07:00" Carbon instance — would be written as the wall-clock time with the
     * offset silently dropped, storing the instant 7 hours off. Converting to a
     * UTC Carbon at this boundary makes the value unambiguous so what lands in the
     * database equals the instant the client actually meant.
     *
     * A naive string carrying no offset is treated as the API's documented UTC
     * instant; the server never guesses a client's local zone.
     */
    public static function utc(string $field, mixed $value): ?Carbon
    {
        if ($value === null || (is_string($value) && trim($value) === '')) {
            return null;
        }

        if ($value instanceof DateTimeInterface) {
            return Carbon::instance($value)->setTimezone('UTC');
        }

        if (! is_scalar($value)) {
            throw self::invalid($field);
        }

        $normalized = preg_replace('/(T\d{2}:\d{2}:\d{2}) (\d{2}:\d{2})$/', '$1+$2', trim((string) $value));

        try {
            return Carbon::parse($normalized, 'UTC')->setTimezone('UTC');
        } catch (\Throwable) {
            throw self::invalid($field);
        }
    }

    /**
     * Normalise every instant the client may have sent for a given model, keyed
     * off the model's own date casts so each write path is handled identically.
     *
     * @param  class-string<Model>  $model
     * @param  array<string, mixed>  $attributes
     * @return array<string, mixed>
     */
    public static function forModel(string $model, array $attributes): array
    {
        foreach (self::dateFields($model) as $field) {
            if (array_key_exists($field, $attributes)) {
                $attributes[$field] = self::utc($field, $attributes[$field]);
            }
        }

        return $attributes;
    }

    /**
     * @param  class-string<Model>  $model
     * @return list<string>
     */
    private static function dateFields(string $model): array
    {
        /** @var Model $instance */
        $instance = new $model;

        $fields = $instance->getDates();

        foreach ($instance->getCasts() as $column => $type) {
            $base = is_string($type) ? explode(':', $type)[0] : $type;

            if (in_array($base, self::DATE_CASTS, true)) {
                $fields[] = $column;
            }
        }

        return array_values(array_unique($fields));
    }

    private static function invalid(string $field): ValidationException
    {
        return ValidationException::withMessages([
            $field => ['The '.str_replace('_', ' ', $field).' must be a valid ISO8601 date.'],
        ]);
    }
}
