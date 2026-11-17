<?php

namespace Modules\Users\Http\Responses;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;
use Modules\Users\Http\Requests\StoreUserRequest;
use Modules\Users\Http\Resources\UserResource;
use Modules\Users\Persistence\Models\User;
use Throwable;

/** As respostas de POST /users fora do 422, que fica no StoreUserRequest (docs/api-contract.md). */
class RegistrationResponses
{
    public static function created(User $user): JsonResponse
    {
        return UserResource::make($user)
            ->additional(['message' => 'User registered successfully.'])
            ->response()
            ->setStatusCode(201);
    }

    public static function emailTaken(): JsonResponse
    {
        return response()->json([
            'message' => StoreUserRequest::MESSAGES['email']['already_taken'],
            'errors' => [StoreUserRequest::item('email', 'already_taken')],
        ], 409);
    }

    public static function limited(int $retryAfter): JsonResponse
    {
        return response()->json([
            'message' => 'Too many registration attempts. Try again later.',
            'errors' => [],
        ], 429, ['Retry-After' => (string) $retryAfter]);
    }

    /** O motivo vai para o log; a resposta não traz detalhe interno, mesmo com APP_DEBUG ligado. */
    public static function failed(Throwable $e): JsonResponse
    {
        Log::error('registration failed', ['error' => $e->getMessage()]);

        return response()->json(['message' => 'Internal server error.', 'errors' => []], 500);
    }
}
