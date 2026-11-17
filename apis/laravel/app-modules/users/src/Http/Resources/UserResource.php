<?php

namespace Modules\Users\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Modules\Users\Persistence\Models\User;

/** O usuário no corpo do 201 de POST /users, dentro de `data` (docs/api-contract.md). */
class UserResource extends JsonResource
{
    /** @return array{id: string, name: string, email: string, created_at: string} */
    public function toArray(Request $request): array
    {
        /** @var User $user */
        $user = $this->resource;

        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'created_at' => $user->created_at->copy()->utc()->format('Y-m-d\TH:i:s\Z'),
        ];
    }
}
