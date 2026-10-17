<?php

namespace Tests\Unit;

use App\Models\Reminder;
use App\Support\Timestamp;
use Carbon\Carbon;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class TimestampTest extends TestCase
{
    public function test_honours_numeric_offset_and_converts_to_utc(): void
    {
        $utc = Timestamp::utc('scheduled_at', '2026-10-18T18:00:00+07:00');

        $this->assertSame('UTC', $utc->tzName);
        $this->assertSame('2026-10-18 11:00:00', $utc->format('Y-m-d H:i:s'));
        $this->assertSame(
            Carbon::parse('2026-10-18T18:00:00+07:00')->getTimestamp(),
            $utc->getTimestamp(),
        );
    }

    public function test_negative_offset_is_converted_to_utc(): void
    {
        $utc = Timestamp::utc('scheduled_at', '2026-10-18T18:00:00-05:00');

        $this->assertSame('2026-10-18 23:00:00', $utc->format('Y-m-d H:i:s'));
    }

    public function test_zulu_and_naive_strings_are_unchanged_as_utc(): void
    {
        $this->assertSame('2026-10-18 11:00:00', Timestamp::utc('a', '2026-10-18T11:00:00Z')->format('Y-m-d H:i:s'));

        // A naive value carries no zone: it is the documented UTC instant, not shifted.
        $this->assertSame('2026-10-18 18:00:00', Timestamp::utc('b', '2026-10-18 18:00:00')->format('Y-m-d H:i:s'));
    }

    public function test_percent_decoded_plus_becomes_a_space_offset_and_still_parses(): void
    {
        // Some clients send "+07:00" which the query parser turns into " 07:00".
        $utc = Timestamp::utc('c', '2026-10-18T18:00:00 07:00');

        $this->assertSame('2026-10-18 11:00:00', $utc->format('Y-m-d H:i:s'));
    }

    public function test_null_and_blank_return_null(): void
    {
        $this->assertNull(Timestamp::utc('due_at', null));
        $this->assertNull(Timestamp::utc('due_at', ''));
        $this->assertNull(Timestamp::utc('due_at', '   '));
    }

    public function test_carbon_instances_are_normalised_to_utc(): void
    {
        $utc = Timestamp::utc('due_at', Carbon::parse('2026-10-18T18:00:00+07:00'));

        $this->assertSame('UTC', $utc->tzName);
        $this->assertSame('2026-10-18 11:00:00', $utc->format('Y-m-d H:i:s'));
    }

    public function test_unparseable_input_is_rejected_with_a_validation_exception(): void
    {
        $this->expectException(ValidationException::class);
        $this->expectExceptionMessage('The scheduled at must be a valid ISO8601 date.');

        Timestamp::utc('scheduled_at', 'not-a-real-date');
    }

    public function test_for_model_only_touches_date_cast_fields(): void
    {
        $normalised = Timestamp::forModel(Reminder::class, [
            'title' => 'keep me',
            'scheduled_at' => '2026-10-18T18:00:00+07:00',
        ]);

        $this->assertSame('keep me', $normalised['title']);
        $this->assertInstanceOf(Carbon::class, $normalised['scheduled_at']);
        $this->assertSame('2026-10-18 11:00:00', $normalised['scheduled_at']->format('Y-m-d H:i:s'));
    }
}
