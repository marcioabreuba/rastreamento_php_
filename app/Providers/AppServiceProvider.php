<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Http\Middleware\TrustProxies;
use Illuminate\Http\Request;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Trust all proxies to correctly capture X-Forwarded-For headers
        TrustProxies::at('*');
        // Trust all forwarded headers
        TrustProxies::withHeaders(Request::HEADER_X_FORWARDED_ALL);
    }
}
