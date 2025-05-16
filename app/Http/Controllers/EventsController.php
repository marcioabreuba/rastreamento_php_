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
use GeoIp2\WebService\Client;
use Esign\ConversionsApi\Objects\DefaultUserData;
use FacebookAds\Object\ServerSide\CustomData;
use FacebookAds\Object\ServerSide\UserData;
use FacebookAds\Object\ServerSide\Content;
use Illuminate\Support\Facades\Config;
use App\Models\User;

class EventsController extends Controller
{
    /**
     * Processa e envia eventos para a Conversions API do Facebook.
     *
     * @param  \Illuminate\Http\Request  $request
     * @return \Illuminate\Http\JsonResponse
     */
    public function send(Request $request)
    {
        try {
            // Obter dados do cabeçalho Content-Type
            $contentType = $request->header('Content-Type');
            $isJson = strpos($contentType, 'application/json') !== false;

            // Validar os dados da requisição
            $validatedData = $request->validate([
                'eventType' => 'required|string|in:Init,PageView,ViewContent,Lead,AddToWishlist,AddToCart,InitiateCheckout,Purchase,Scroll_25,Scroll_50,Scroll_75,Scroll_90,Timer_1min,PlayVideo,ViewVideo_25,ViewVideo_50,ViewVideo_75,ViewVideo_90,ViewHomepage,ViewShop,ViewCategory,ViewCart,ShippingInfo,PaymentInfo,PurchaseCreditCard,PurchasePix,PurchaseBoleto,PurchasePixPaid,PurchaseHigherValue,PurchaseCreditCardDeclined,Registration,Search,ViewSearchResults',
                'contentId' => 'nullable|string',
                'contentType' => 'nullable|string',
                'contentName' => 'nullable|string',
                'currency' => 'nullable|string|size:3',
                'value' => 'nullable|numeric',
                'eventID' => 'nullable|string',
                'search_string' => 'nullable|string',
                'status' => 'nullable|boolean',
                'predicted_ltv' => 'nullable|numeric',
                'num_items' => 'nullable|integer',
                'userId' => 'nullable|string',
                'userAgent' => 'nullable|string',
                '_fbp' => 'nullable|string',
                '_fbc' => 'nullable|string',
                'event_source_url' => 'nullable|string',
            ]);

            // Caminhos personalizados para o Init
            if ($validatedData['eventType'] === 'Init') {
                // Processar evento de inicialização
                // ...
                return response()->json(['status' => 'success', 'message' => 'Init event processed']);
            }

            // Criar nome da classe de evento dinamicamente
            $eventClassName = '\\App\\Events\\' . $validatedData['eventType'];

            // Verificar se a classe existe
            if (!class_exists($eventClassName)) {
                return response()->json([
                    'status' => 'error',
                    'message' => "Event class {$eventClassName} not found"
                ], 400);
            }

            // Criar evento e enviá-lo
            $event = $eventClassName::create();

            // Adicionar parâmetros extras se fornecidos
            if (isset($validatedData['contentId'])) {
                $event->setContentIds([$validatedData['contentId']]);
            }

            if (isset($validatedData['contentType'])) {
                $event->setContentType($validatedData['contentType']);
            }

            if (isset($validatedData['contentName'])) {
                $event->setContentName($validatedData['contentName']);
            }

            if (isset($validatedData['currency']) && isset($validatedData['value'])) {
                $customData = new CustomData();
                $customData->setCurrency($validatedData['currency']);
                $customData->setValue($validatedData['value']);
                
                if (isset($validatedData['search_string'])) {
                    $customData->setSearchString($validatedData['search_string']);
                }
                
                if (isset($validatedData['status'])) {
                    $customData->setStatus($validatedData['status'] ? 'active' : 'inactive');
                }
                
                if (isset($validatedData['predicted_ltv'])) {
                    $customData->setPredictedLtv($validatedData['predicted_ltv']);
                }
                
                if (isset($validatedData['num_items'])) {
                    $customData->setNumItems($validatedData['num_items']);
                }
                
                $event->setCustomData($customData);
            }

            // Definir URL da origem do evento se fornecida
            if (isset($validatedData['event_source_url'])) {
                $event->setEventSourceUrl($validatedData['event_source_url']);
            } else {
                $event->setEventSourceUrl($request->headers->get('referer') ?? config('app.url'));
            }

            // Definir ID do evento se fornecido
            if (isset($validatedData['eventID'])) {
                $event->setEventId($validatedData['eventID']);
            }

            // Definir dados de usuário personalizados
            $userData = ConversionsApi::getUserData();
            
            if (isset($validatedData['userId'])) {
                $userData->setExternalId(hash('sha256', $validatedData['userId']));
            }
            
            if (isset($validatedData['_fbp'])) {
                $userData->setFbp($validatedData['_fbp']);
            }
            
            if (isset($validatedData['_fbc'])) {
                $userData->setFbc($validatedData['_fbc']);
            }
            
            if (isset($validatedData['userAgent'])) {
                $userData->setClientUserAgent($validatedData['userAgent']);
            } else {
                $userData->setClientUserAgent($request->header('User-Agent'));
            }
            
            $event->setUserData($userData);

            // Enviar evento para a API
            $result = ConversionsApi::clearEvents()->addEvent($event)->sendEvents();

            // Retornar resposta
            return response()->json([
                'status' => 'success',
                'message' => 'Event sent successfully',
                'event_type' => $validatedData['eventType'],
                'event_id' => $event->getEventId(),
                'timestamp' => $event->getEventTime()
            ]);
        } catch (\Exception $e) {
            // Registrar erro e retornar resposta de erro
            Log::error('Error sending event: ' . $e->getMessage(), [
                'exception' => $e,
                'request' => $request->all()
            ]);
            
            return response()->json([
                'status' => 'error',
                'message' => 'Error processing event: ' . $e->getMessage()
            ], 500);
        }
    }
}