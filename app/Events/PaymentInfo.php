<?php

namespace App\Events;
use Esign\ConversionsApi\Facades\ConversionsApi;
use FacebookAds\Object\ServerSide\ActionSource;
use FacebookAds\Object\ServerSide\Event;
use FacebookAds\Object\ServerSide\UserData;

class PaymentInfo extends Event
{
    public static function create(): static
    {
        return (new static())
            ->setActionSource(ActionSource::WEBSITE)
            ->setEventName('PaymentInfo')
            ->setEventTime(time())
            ->setEventId((string) \Illuminate\Support\Str::uuid())
            ->setUserData(ConversionsApi::getUserData());
    }
} 