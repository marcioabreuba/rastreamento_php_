<?php

namespace App\Http\Controllers;

use App\Events\PageView;
use App\Events\ViewContent;
use App\Events\Lead;
use App\Events\AddToWishlist;
use App\Events\AddToCart;
use App\Events\InitiateCheckout;
use App\Events\Purchase;
use App\Events\Scroll_25;
use App\Events\Scroll_50;
use App\Events\Scroll_75;
use App\Events\Scroll_90;
use App\Events\Timer_1min;
use App\Events\PlayVideo;
use App\Events\ViewVideo_25;
use App\Events\ViewVideo_50;
use App\Events\ViewVideo_75;
use App\Events\ViewVideo_90;
use Esign\ConversionsApi\Facades\ConversionsApi;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use GeoIp2\Database\Reader;
use Esign\ConversionsApi\Objects\DefaultUserData;
use FacebookAds\Object\ServerSide\CustomData;
use FacebookAds\Object\ServerSide\UserData;
use FacebookAds\Object\ServerSide\Content;
use Illuminate\Support\Facades\Config;
use App\Models\User;

class EventsController extends Controller
{
    public function send(Request $request)
    {
        // Log::info('Recebendo Payload:', $request->all());
        try {
            // Determine client IP (use X-Forwarded-For headers or remote)
            $ip = $request->header('CF-Connecting-IP')
                ?? $request->header('X-Forwarded-For');
            $ip = $ip ? trim(explode(',', $ip)[0]) : $request->ip();
            // Use local GeoLite2 database for geolocation
            $reader = new Reader(storage_path('app/geoip/GeoLite2-City.mmdb'));
            $record = $reader->city($ip);
            // Common processing
            $country = strtolower($record->country->isoCode);
            $state = strtolower($record->mostSpecificSubdivision->isoCode);
            $city = strtolower($record->city->name);
            $postalCode = $record->postal->code;
            // Clean accents and non-letters
            $city = strtr($city, [
                'á'=>'a','à'=>'a','ã'=>'a','â'=>'a',
                'é'=>'e','ê'=>'e','í'=>'i','ó'=>'o',
                'ô'=>'o','õ'=>'o','ú'=>'u','ç'=>'c'
            ]);
            $city = preg_replace('/[^a-z]/','',$city);
            // Hash values
            $hashedCountry = hash('sha256',$country);
            $hashedState = hash('sha256',$state);
            $hashedCity = hash('sha256',$city);
            $hashedPostalCode = hash('sha256',$postalCode);
        } catch (\GeoIp2\Exception\AddressNotFoundException $e) {
            // Expected for private/internal IP
            $country = $state = $city = $postalCode = null;
            $hashedCountry = $hashedState = $hashedCity = $hashedPostalCode = null;
            Log::info('Consulta GeoIP: Endereço não encontrado.', ['ip'=>$ip,'message'=>$e->getMessage()]);
        } catch (\Exception $e) {
            // Unhandled errors
            $country = $state = $city = $postalCode = null;
            $hashedCountry = $hashedState = $hashedCity = $hashedPostalCode = null;
            Log::error('Erro inesperado ao consultar GeoIP: '.$e->getMessage(), ['ip'=>$ip]);
        }
        try {
            // Apenas para quem usa a minha Api
            $contentId = $request->post('contentId');
            $domains = config('conversions.domains');
            if (isset($domains[$contentId])) {
                $config = $domains[$contentId];
                Config::set('conversions-api.pixel_id', $config['pixel_id']);
                Config::set('conversions-api.access_token', $config['access_token']);
                Config::set('conversions-api.test_code', $config['test_code']);
            } else {
                Log::info('[EVENTS] Configuração não encontrada para contentId: ' . $contentId);
            }
            
            $request->merge([
                'ph' => preg_replace('/\D/', '', $request->input('ph'))
            ]);

            $validatedData = $request->validate([
                'eventType' => 'required|string|in:Init,PageView,ViewContent,Lead,AddToWishlist,AddToCart,InitiateCheckout,Purchase,Scroll_25,Scroll_50,Scroll_75,Scroll_90,Timer_1min,PlayVideo,ViewVideo_25,ViewVideo_50,ViewVideo_75,ViewVideo_90',
                'event_source_url' => 'nullable|string',
                '_fbc' => 'nullable|string', 
                '_fbp' => 'nullable|string',
                'userId' => 'nullable|string',
                'fn' => 'nullable|string|max:255',
                'ln' => 'nullable|string|max:255',
                'em' => 'nullable|email|max:255',
                'ph' => 'nullable|string|max:15',
            ]);

            $eventType = $validatedData['eventType'];
            $event_source_url = $validatedData['event_source_url'];
            $_fbc = $validatedData['_fbc'];
            $_fbp = $validatedData['_fbp'];
            $userId = $validatedData['userId'];
            
            $initData = ConversionsApi::getUserData();
            
            if ($eventType == "Init") {
                return response()->json([
                    'ct' => $city,
                    'st' => $state,
                    'zp' => $postalCode,
                    'country' => $country,
                    'client_ip_address' => $initData->getClientIpAddress(),
                    'client_user_agent' => $initData->getClientUserAgent(),
                    'fbc' => $_fbc,
                    'fbp' => $_fbp,
                    'external_id' => $userId
                ]);
            } elseif ($eventType == "PageView") {
                $user = User::where('external_id', $userId)->first();
                if (!$user) {
                    User::create([
                        'content_id' => $contentId,
                        'external_id' => $userId,
                        'client_ip_address' => $initData->getClientIpAddress(),
                        'client_user_agent' => $initData->getClientUserAgent(),
                        'fbp' => $_fbp,
                        'fbc' => $_fbc,
                        'country' => $country,
                        'st' => $state,
                        'ct' => $city,
                        'zp' => $postalCode,
                        'fn' => $validatedData['fn'] ?? '',
                        'ln' => $validatedData['ln'] ?? '',
                        'em' => $validatedData['em'] ?? '',
                        'ph' => $validatedData['ph'] ?? '',
                    ]);
                }
            }

            // Cria dinamicamente o evento com base no tipo
            $eventClass = "App\\Events\\{$eventType}";
            if (!class_exists($eventClass)) {
                return response()->json(['error' => 'Tipo de evento inválido.'], 400);
            }

            $event = $eventClass::create()
                ->setEventSourceUrl($event_source_url)
                ->setCustomData(
                    (new CustomData())->setContentIds([$contentId])
                );
            $eventID = $event->getEventId();

            $advancedMatching = $event->getUserData()
                ->setFbc($_fbc)
                ->setFbp($_fbp)
                ->setState($state)
                ->setCountryCode($country)
                ->setCity($city)
                ->setZipCode($postalCode)
                ->setExternalId($userId);

            if (isset($validatedData['fn']) && !empty($validatedData['fn'])) {
                $advancedMatching->setFirstName($validatedData['fn']);
            }

            if (isset($validatedData['ln']) && !empty($validatedData['ln'])) {
                $advancedMatching->setLastName($validatedData['ln']);
            }

            if (isset($validatedData['em']) && !empty($validatedData['em'])) {
                $advancedMatching->setEmail($validatedData['em']);
            }

            if (isset($validatedData['ph']) && !empty($validatedData['ph'])) {
                $advancedMatching->setPhone($validatedData['ph']);
            }

            $log = [
                'event_id' => $event->getEventId(),
                'event_name' => $event->getEventName(),
                'event_time' => $event->getEventTime(),
                'event_source_url' => $event->getEventSourceUrl(),
                'user_data' => [
                    'client_user_agent' => $event->getUserData()->getClientUserAgent(),
                    'client_ip_address' => $event->getUserData()->getClientIpAddress(),
                    'fbc' => $event->getUserData()->getFbc(),
                    'fbp' => $event->getUserData()->getFbp(),
                    'external_id' => $userId,
                    'country' => $advancedMatching->getCountryCode(),
                    'state' => $advancedMatching->getState(),
                    'city' => $advancedMatching->getCity(),
                    'postal_code' => $advancedMatching->getZipCode(),
                    'fn' => $validatedData['fn'] ?? '',
                    'ln' => $validatedData['ln'] ?? '',
                    'em' => $validatedData['em'] ?? '',
                    'ph' => $validatedData['ph'] ?? '',
                ],
            ];

            $event->setUserData($advancedMatching);
            ConversionsApi::addEvent($event)->sendEvents();

            Log::channel('Events')->info(json_encode($log, JSON_PRETTY_PRINT));

            return response()->json(['eventID' => $eventID, 'external_id' => $userId]);
        } catch (\Exception $e) {
            Log::error('Erro no envio do evento:', [
                'message' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json(['error' => 'Erro interno no servidor.'], 500);
        }
    }
}