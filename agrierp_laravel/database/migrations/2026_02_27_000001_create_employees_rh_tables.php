<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `payslips.accounting_entry_id` reste nullable sans contrainte FK, même
 * principe que partout ailleurs dans ce projet (Sprint 10).
 * `attendance_records` : unique (employee_id, attendance_date) — un seul
 * pointage par employé et par jour, contrainte déjà portée par le schéma
 * documenté, pas ajoutée ici.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('employees', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('first_name', 100);
            $table->string('last_name', 100);
            $table->string('position', 100)->nullable();
            $table->decimal('base_salary', 14, 2)->nullable();
            $table->date('hire_date')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('payslips', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employee_id')->constrained('employees')->restrictOnDelete();
            $table->date('period_month');
            $table->decimal('gross_salary', 14, 2);
            $table->decimal('absence_deduction', 14, 2)->default(0);
            $table->decimal('cnss_deduction', 14, 2)->default(0); // 3.6%
            $table->decimal('net_salary', 14, 2);
            $table->uuid('accounting_entry_id')->nullable();
            $table->timestamps();
        });

        Schema::create('attendance_records', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('employee_id')->constrained('employees')->restrictOnDelete();
            $table->date('attendance_date');
            $table->time('check_in')->nullable();
            $table->time('check_out')->nullable();
            $table->enum('status', ['present', 'absent', 'conge', 'maladie'])->default('present');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['employee_id', 'attendance_date']);
        });

        Schema::create('internships', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('first_name', 100);
            $table->string('last_name', 100);
            $table->string('school', 150)->nullable();
            $table->date('start_date');
            $table->date('end_date')->nullable();
            $table->decimal('monthly_fee', 14, 2)->nullable();
            $table->timestamps();
        });

        Schema::create('internship_absences', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('internship_id')->constrained('internships')->cascadeOnDelete();
            $table->date('absence_date');
            $table->text('reason')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('internship_absences');
        Schema::dropIfExists('internships');
        Schema::dropIfExists('attendance_records');
        Schema::dropIfExists('payslips');
        Schema::dropIfExists('employees');
    }
};
