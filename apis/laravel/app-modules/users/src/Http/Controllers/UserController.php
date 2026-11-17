<?php

namespace Modules\Users\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Modules\Users\Core\Exceptions\EmailAlreadyTaken;
use Modules\Users\Core\Exceptions\RegistrationLimited;
use Modules\Users\Core\UseCases\RegisterUser;
use Modules\Users\Http\Requests\StoreUserRequest;
use Modules\Users\Http\Responses\RegistrationResponses;
use Throwable;

/** POST /users (docs/api-contract.md): toda indisponibilidade responde 500. */
class UserController
{
    public function store(StoreUserRequest $request, RegisterUser $register): JsonResponse
    {
        try {
            $user = $register->execute($request->toDto(), (string) $request->ip());
        } catch (EmailAlreadyTaken) {
            return RegistrationResponses::emailTaken();
        } catch (RegistrationLimited $e) {
            return RegistrationResponses::limited($e->retryAfter);
        } catch (Throwable $e) {
            return RegistrationResponses::failed($e);
        }

        return RegistrationResponses::created($user);
    }
}
