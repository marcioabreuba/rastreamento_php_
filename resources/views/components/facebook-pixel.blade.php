@props(['pixelId' => config('conversions-api.pixel_id')])

<!-- Facebook Pixel Code -->
<script>
!function(f,b,e,v,n,t,s)
{if(f.fbq)return;n=f.fbq=function(){n.callMethod?
n.callMethod.apply(n,arguments):n.queue.push(arguments)};
if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
n.queue=[];t=b.createElement(e);t.async=!0;
t.src=v;s=b.getElementsByTagName(e)[0];
s.parentNode.insertBefore(t,s)}(window, document,'script',
'https://connect.facebook.net/en_US/fbevents.js');

// Inicialização segura do pixel
fbq('init', '{{ $pixelId }}');
fbq('track', 'PageView');

// Objeto global de rastreamento seguro
window.PixelTracker = {
    track: function(eventName, params) {
        if (typeof fbq === 'function') {
            // Gera um ID de evento único para deduplicação
            const eventId = 'event-' + Math.random().toString(36).substr(2, 9);
            
            // Configura os parâmetros padrão
            const defaultParams = {
                event_source_url: window.location.href,
                _fbp: (document.cookie.match('(^|;)\\s*_fbp\\s*=\\s*([^;]+)') || [])[2],
                _fbc: (document.cookie.match('(^|;)\\s*_fbc\\s*=\\s*([^;]+)') || [])[2],
                userId: localStorage.getItem('userId') || '',
                contentId: '{{ config("app.url") }}'
            };
            
            // Mescla os parâmetros padrão com os específicos
            const eventParams = {...defaultParams, ...params, eventID: eventId};
            
            // Rastreia via pixel
            fbq('track', eventName, eventParams, {eventID: eventId});
            
            // Rastreia via servidor
            fetch('/events/send', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]')?.content || ''
                },
                body: JSON.stringify({
                    eventType: eventName,
                    ...eventParams
                })
            })
            .then(response => response.json())
            .then(data => console.log('Evento enviado:', eventName, data))
            .catch(error => console.error('Erro ao enviar evento:', error));
        }
    }
};

// Carregar scripts de eventos personalizados
document.addEventListener('DOMContentLoaded', function() {
    // Detecta os elementos do DOM e adiciona eventos com verificação segura
    function safeAddEventListener(selector, eventType, eventName, dataFn) {
        const elements = document.querySelectorAll(selector);
        if (elements && elements.length > 0) {
            elements.forEach(el => {
                el.addEventListener(eventType, function(e) {
                    const data = dataFn ? dataFn(e, el) : {};
                    window.PixelTracker.track(eventName, data);
                });
            });
        }
    }

    // Exemplos de rastreamento seguro
    safeAddEventListener('a[href*="shop"]', 'click', 'ViewShop');
    safeAddEventListener('.category-link', 'click', 'ViewCategory');
    
    // Monitora rolagem da página
    let scrolled25 = false, scrolled50 = false, scrolled75 = false, scrolled90 = false;
    window.addEventListener('scroll', function() {
        const scrollPercentage = (window.scrollY / (document.documentElement.scrollHeight - window.innerHeight)) * 100;
        
        if (!scrolled25 && scrollPercentage >= 25) {
            scrolled25 = true;
            window.PixelTracker.track('Scroll_25');
        }
        if (!scrolled50 && scrollPercentage >= 50) {
            scrolled50 = true;
            window.PixelTracker.track('Scroll_50');
        }
        if (!scrolled75 && scrollPercentage >= 75) {
            scrolled75 = true;
            window.PixelTracker.track('Scroll_75');
        }
        if (!scrolled90 && scrollPercentage >= 90) {
            scrolled90 = true;
            window.PixelTracker.track('Scroll_90');
        }
    });
    
    // Timer para 1 minuto na página
    setTimeout(function() {
        window.PixelTracker.track('Timer_1min');
    }, 60000);
});
</script>
<!-- End Facebook Pixel Code --> 