<?php

namespace Modules\Users\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;
use Modules\Users\Exceptions\EmailAlreadyTaken;
use Modules\Users\Exceptions\RegistrationLimited;
use Modules\Users\Http\Requests\StoreUserRequest;
use Modules\Users\UseCases\RegisterUser;
use Throwable;

/**
 * POST /users (docs/api-contract.md). Toda indisponibilidade responde 500: o motivo vai
 * para o log, e a resposta não traz detalhe interno mesmo com APP_DEBUG ligado.
 */
class UserController
{
    public function store(StoreUserRequest $request, RegisterUser $register): JsonResponse
    {
        try {
            $user = $register->execute($request->string('name')->value(), $request->string('email')->value(), (string) $request->ip());
        } catch (EmailAlreadyTaken) {
            return response()->json([
                'message' => StoreUserRequest::MESSAGES['email']['already_taken'],
                'errors' => [StoreUserRequest::item('email', 'already_taken')],
            ], 409);
        } catch (RegistrationLimited $limited) {
            return response()->json([
                'message' => 'Too many registration attempts. Try again later.',
                'errors' => [],
            ], 429, ['Retry-After' => (string) $limited->retryAfter]);
        } catch (Throwable $e) {
            Log::error('registration failed', ['error' => $e->getMessage()]);

            return response()->json(['message' => 'Internal server error.', 'errors' => []], 500);
        }

        return response()->json([
            'data' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'created_at' => $user->created_at->utc()->format('Y-m-d\TH:i:s\Z'),
            ],
            'message' => 'User registered successfully.',
        ], 201);
    }
}
