<?php

use Illuminate\Support\Facades\Route;
use Modules\Health\Http\Controllers\HealthController;

Route::get('/health', HealthController::class);
