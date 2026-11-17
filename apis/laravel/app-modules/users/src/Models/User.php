<?php

namespace Modules\Users\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Table;
use Illuminate\Database\Eloquent\Model;

#[Table(keyType: 'string', incrementing: false)]
#[Fillable('name', 'email')]
class User extends Model
{
    //
}
