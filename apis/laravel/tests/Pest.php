<?php

use Tests\TestCase;

pest()->extend(TestCase::class)->in('Feature', '../app-modules/*/tests');
