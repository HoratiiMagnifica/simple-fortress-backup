#!/usr/bin/env python3
# web/app.py - FortressBackup web interface

import os
import subprocess
from flask import Flask, render_template, request, redirect, url_for, flash, session
from functools import wraps
import hashlib

app = Flask(__name__)
app.secret_key = os.urandom(24)

# Configuration
WEB_PORT = 5000
BACKUP_CONFIG = "/etc/fortressbackup-client.conf"
BACKUP_SCRIPT = "/usr/local/bin/fortress-backup"
LOG_FILE = "/var/log/fortressbackup.log"
AUTH_LOG = "/var/log/auth.log"
PASSWORD_FILE = "/opt/fortressbackup-web/password.hash"

# Authentication decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

# Password verification
def check_password(password):
    try:
        with open(PASSWORD_FILE, 'r') as f:
            stored_hash = f.read().strip()
        return hashlib.sha256(password.encode()).hexdigest() == stored_hash
    except:
        return False

# Read backup configuration
def read_backup_config():
    backups = []
    try:
        if os.path.exists(BACKUP_CONFIG):
            with open(BACKUP_CONFIG, 'r') as f:
                content = f.read()
            
            config_dict = {}
            for line in content.split('\n'):
                if '=' in line and not line.startswith('#'):
                    key, value = line.split('=', 1)
                    config_dict[key.strip()] = value.strip().strip('"')
            
            # Legacy format (single backup)
            if 'SOURCES' in config_dict and 'BACKUP_1_SOURCES' not in config_dict:
                backups.append({
                    'id': 1,
                    'enabled': 'true',
                    'sources': config_dict['SOURCES'],
                    'time': config_dict.get('BACKUP_TIME', '02:00'),
                    'schedule': 'daily'
                })
            else:
                # Multi-backup format
                i = 1
                while f"BACKUP_{i}_SOURCES" in config_dict:
                    backup = {
                        'id': i,
                        'enabled': config_dict.get(f"BACKUP_{i}_ENABLED", 'true'),
                        'sources': config_dict[f"BACKUP_{i}_SOURCES"],
                        'time': config_dict.get(f"BACKUP_{i}_TIME", '02:00'),
                        'schedule': config_dict.get(f"BACKUP_{i}_SCHEDULE", 'daily')
                    }
                    backups.append(backup)
                    i += 1
    except Exception as e:
        print(f"Error reading config: {e}")
    
    return backups

# Save backup configuration
def save_backup_config(backups):
    try:
        existing = {}
        if os.path.exists(BACKUP_CONFIG):
            with open(BACKUP_CONFIG, 'r') as f:
                for line in f:
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        existing[key.strip()] = value.strip()
        
        with open(BACKUP_CONFIG, 'w') as f:
            f.write(f"SERVER_IP={existing.get('SERVER_IP', '')}\n")
            f.write(f"SSH_PORT={existing.get('SSH_PORT', '22')}\n")
            f.write(f"BACKUP_PORT={existing.get('BACKUP_PORT', '2222')}\n")
            f.write(f"BACKUP_TIME={existing.get('BACKUP_TIME', '02:00')}\n")
            f.write("\n")
            
            for backup in backups:
                f.write(f"BACKUP_{backup['id']}_ENABLED={backup.get('enabled', 'true')}\n")
                f.write(f"BACKUP_{backup['id']}_SOURCES={backup['sources']}\n")
                f.write(f"BACKUP_{backup['id']}_TIME={backup.get('time', '02:00')}\n")
                f.write(f"BACKUP_{backup['id']}_SCHEDULE={backup.get('schedule', 'daily')}\n")
                f.write("\n")
    except Exception as e:
        print(f"Error saving config: {e}")

# Update crontab - Simple and reliable version
def update_crontab(backups):
    cron_lines = []
    for backup in backups:
        if backup.get('enabled', 'true') == 'true':
            time = backup.get('time', '02:00')
            minute, hour = time.split(':')
            schedule = backup.get('schedule', 'daily')
            
            if schedule == 'weekly':
                cron_line = f"{minute} {hour} * * 0"
            elif schedule == 'monthly':
                cron_line = f"{minute} {hour} 1 * *"
            else:
                cron_line = f"{minute} {hour} * * *"
            
            cron_lines.append(f"{cron_line} {BACKUP_SCRIPT} --backup-id {backup['id']} >> {LOG_FILE} 2>&1")
    
    # Get current crontab
    try:
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
        current_cron = result.stdout if result.returncode == 0 else ""
    except:
        current_cron = ""
    
    # Remove old fortress-backup entries
    new_lines = []
    for line in current_cron.split('\n'):
        if line.strip() and 'fortress-backup' not in line:
            new_lines.append(line.rstrip())
    
    # Add new entries
    for line in cron_lines:
        new_lines.append(line)
    
    # Create temporary file with guaranteed newline
    temp_file = '/tmp/crontab_fortressbackup.tmp'
    try:
        with open(temp_file, 'w') as f:
            for line in new_lines:
                f.write(line + '\n')
            if not new_lines:
                f.write('# No backup jobs\n')
        
        subprocess.run(['crontab', temp_file], check=True, capture_output=True)
        print("Cron updated successfully")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"Error updating crontab: {e.stderr}")
        return False
    except Exception as e:
        print(f"Error: {e}")
        return False
    finally:
        if os.path.exists(temp_file):
            os.unlink(temp_file)

# Get backup logs
def get_backup_logs(lines=100):
    try:
        if os.path.exists(LOG_FILE):
            result = subprocess.run(['tail', '-n', str(lines), LOG_FILE], capture_output=True, text=True)
            return result.stdout if result.stdout else "No backup logs found"
        return "Log file does not exist. Backups have not been run yet."
    except Exception as e:
        return f"Error reading logs: {e}"

# Get access logs
def get_access_logs(lines=50):
    try:
        if os.path.exists(AUTH_LOG):
            result = subprocess.run(['tail', '-n', str(lines), AUTH_LOG], capture_output=True, text=True)
            lines = result.stdout.split('\n')
            ssh_logs = [l for l in lines if 'sshd' in l]
            return '\n'.join(ssh_logs[-lines:]) if ssh_logs else "No SSH logs found"
        return "Access log file not found"
    except Exception as e:
        return f"Error reading access logs: {e}"

# Get free space on backup server
def get_free_space():
    try:
        if os.path.exists(BACKUP_CONFIG):
            with open(BACKUP_CONFIG, 'r') as f:
                content = f.read()
                server_ip = None
                ssh_port = 22
                for line in content.split('\n'):
                    if line.startswith('SERVER_IP='):
                        server_ip = line.split('=')[1].strip()
                    elif line.startswith('SSH_PORT='):
                        ssh_port = line.split('=')[1].strip()
                
                if server_ip:
                    result = subprocess.run(
                        ['ssh', '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=no',
                         '-i', '/root/.ssh/id_ed25519_fortress', '-p', str(ssh_port),
                         f'backupuser@{server_ip}', 'df -h /backups 2>/dev/null || echo "NOT_AVAILABLE"'],
                        capture_output=True,
                        text=True
                    )
                    output = result.stdout
                    if output and 'NOT_AVAILABLE' not in output:
                        lines = output.split('\n')
                        if len(lines) > 1:
                            parts = lines[1].split()
                            if len(parts) >= 5:
                                return {
                                    'total': parts[1],
                                    'used': parts[2],
                                    'free': parts[3],
                                    'use_percent': parts[4]
                                }
        return None
    except Exception as e:
        print(f"Error getting free space: {e}")
        return None

# Run backup
def run_backup():
    try:
        if os.path.exists(BACKUP_SCRIPT):
            result = subprocess.run([BACKUP_SCRIPT], capture_output=True, text=True, timeout=300)
            with open(LOG_FILE, 'a') as f:
                f.write(f"\n[WEB] Backup started via web interface:\n")
                f.write(result.stdout)
                if result.stderr:
                    f.write(result.stderr)
            return result.returncode == 0, result.stdout + result.stderr
        return False, f"Backup script not found: {BACKUP_SCRIPT}"
    except subprocess.TimeoutExpired:
        return False, "Backup exceeded time limit (5 minutes)"
    except Exception as e:
        return False, str(e)

# Routes
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        password = request.form.get('password')
        if check_password(password):
            session['logged_in'] = True
            session.permanent = True
            flash('Login successful', 'success')
            return redirect(url_for('index'))
        else:
            flash('Invalid password', 'error')
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.pop('logged_in', None)
    flash('Logged out', 'success')
    return redirect(url_for('login'))

@app.route('/')
@login_required
def index():
    free_space = get_free_space()
    logs = get_backup_logs(20)
    return render_template('index.html', free_space=free_space, logs=logs)

@app.route('/backups')
@login_required
def backups():
    backups_list = read_backup_config()
    return render_template('backups.html', backups=backups_list)

@app.route('/backups/add', methods=['POST'])
@login_required
def add_backup():
    sources = request.form.get('sources')
    time = request.form.get('time')
    schedule = request.form.get('schedule')
    
    if not sources or not time:
        flash('Please fill all fields', 'error')
        return redirect(url_for('backups'))
    
    backups_list = read_backup_config()
    new_id = max([b['id'] for b in backups_list], default=0) + 1
    
    backups_list.append({
        'id': new_id,
        'enabled': 'true',
        'sources': sources,
        'time': time,
        'schedule': schedule
    })
    
    save_backup_config(backups_list)
    update_crontab(backups_list)
    flash('Backup added successfully', 'success')
    return redirect(url_for('backups'))

@app.route('/backups/delete/<int:backup_id>')
@login_required
def delete_backup(backup_id):
    backups_list = [b for b in read_backup_config() if b['id'] != backup_id]
    save_backup_config(backups_list)
    update_crontab(backups_list)
    flash('Backup deleted', 'success')
    return redirect(url_for('backups'))

@app.route('/backups/toggle/<int:backup_id>')
@login_required
def toggle_backup(backup_id):
    backups_list = read_backup_config()
    for backup in backups_list:
        if backup['id'] == backup_id:
            current = backup.get('enabled', 'true')
            backup['enabled'] = 'false' if current == 'true' else 'true'
            break
    
    save_backup_config(backups_list)
    update_crontab(backups_list)
    flash('Backup status changed', 'success')
    return redirect(url_for('backups'))

@app.route('/logs')
@login_required
def logs():
    lines = request.args.get('lines', 100, type=int)
    backup_logs = get_backup_logs(lines)
    access_logs = get_access_logs(lines)
    return render_template('logs.html', backup_logs=backup_logs, access_logs=access_logs)

@app.route('/run_now')
@login_required
def run_now():
    success, output = run_backup()
    if success:
        flash('Backup started successfully', 'success')
    else:
        flash(f'Error starting backup: {output[:200]}', 'error')
    return redirect(url_for('index'))

@app.route('/settings', methods=['GET', 'POST'])
@login_required
def settings():
    if request.method == 'POST':
        old_pass = request.form.get('old_password')
        new_pass = request.form.get('new_password')
        confirm_pass = request.form.get('confirm_password')
        
        if not check_password(old_pass):
            flash('Current password is incorrect', 'error')
            return redirect(url_for('settings'))
        
        if new_pass != confirm_pass:
            flash('New passwords do not match', 'error')
            return redirect(url_for('settings'))
        
        if len(new_pass) < 4:
            flash('Password must be at least 4 characters', 'error')
            return redirect(url_for('settings'))
        
        new_hash = hashlib.sha256(new_pass.encode()).hexdigest()
        with open(PASSWORD_FILE, 'w') as f:
            f.write(new_hash)
        
        flash('Password changed successfully', 'success')
        return redirect(url_for('settings'))
    
    return render_template('settings.html')

if __name__ == '__main__':
    port = int(os.environ.get('WEB_PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)