<?php

namespace Modules\Users\Models;

use Illuminate\Database\Eloquent\Model;

class User extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';
}
