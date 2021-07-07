describe HybridPlatformsConductor::ActionsExecutor do

  context 'when checking connector plugin ssh' do

    context 'when checking remote actions' do

      it 'executes bash commands remotely' do
        with_test_platform_for_remote_testing(
          expected_cmds: [[%r{.+/ssh hpc\.node /bin/bash <<'HPC_EOF'\nbash_cmd.bash\nHPC_EOF}, proc { [0, 'Bash commands executed on node', ''] }]],
          expected_stdout: 'Bash commands executed on node'
        ) do
          test_connector.remote_bash('bash_cmd.bash')
        end
      end

      it 'executes bash commands remotely from a SecretString' do
        with_test_platform_for_remote_testing(
          expected_cmds: [[%r{.+/ssh hpc\.node /bin/bash <<'HPC_EOF'\nbash_cmd.bash\nHPC_EOF}, proc { [0, 'Bash commands executed on node', ''] }]],
          expected_stdout: 'Bash commands executed on node'
        ) do
          test_connector.remote_bash(SecretString.new('bash_cmd.bash', silenced_str: '__INVALID_BASH__'))
        end
      end

      it 'executes bash commands remotely with timeout' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{.+/ssh hpc\.node /bin/bash <<'HPC_EOF'\nbash_cmd.bash\nHPC_EOF},
              proc do |_cmd, log_to_file: nil, log_to_stdout: true, log_stdout_to_io: nil, log_stderr_to_io: nil, expected_code: 0, timeout: nil, no_exception: false|
                expect(timeout).to eq 5
                [0, '', '']
              end
            ]
          ],
          timeout: 5
        ) do
          test_connector.remote_bash('bash_cmd.bash')
        end
      end

      it 'executes interactive commands remotely' do
        with_test_platform_for_remote_testing do
          expect(test_connector).to receive(:system) do |cmd|
            expect(cmd).to match(%r{^.+/ssh hpc\.node$})
          end
          test_connector.remote_interactive
        end
      end

      it 'copies files remotely' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{cd /path/to && tar\s+--create\s+--gzip\s+--file -\s+src.file \| /.+/ssh\s+hpc\.node\s+"tar\s+--extract\s+--gunzip\s+--file -\s+--directory /remote_path/to/dst.dir\s+--owner root\s+"},
              proc { [0, '', ''] }
            ]
          ]
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir')
        end
      end

      it 'copies files remotely with timeout' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{cd /path/to && tar\s+--create\s+--gzip\s+--file -\s+src.file \| /.+/ssh\s+hpc\.node\s+"tar\s+--extract\s+--gunzip\s+--file -\s+--directory /remote_path/to/dst.dir\s+--owner root\s+"},
              proc do |_cmd, log_to_file: nil, log_to_stdout: true, log_stdout_to_io: nil, log_stderr_to_io: nil, expected_code: 0, timeout: nil, no_exception: false|
                expect(timeout).to eq 5
                [0, '', '']
              end
            ]
          ],
          timeout: 5
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir')
        end
      end

      it 'executes really big bash commands remotely' do
        cmd = "echo #{'1' * 131_060}"
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{.+/hpc_temp_cmds_.+\.sh$},
              proc do |received_cmd|
                expect(File.read(received_cmd)).to match(%r{.+/ssh hpc\.node /bin/bash <<'HPC_EOF'\n#{Regexp.escape(cmd)}\nHPC_EOF})
                [0, 'Bash commands executed on node', '']
              end
            ]
          ],
          expected_stdout: 'Bash commands executed on node'
        ) do
          # Use an argument that exceeds the max arg length limit
          test_connector.remote_bash(cmd)
        end
      end

      it 'executes really big bash commands remotely using a SecretString' do
        cmd = "echo #{'1' * 131_060}"
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{.+/hpc_temp_cmds_.+\.sh$},
              proc do |received_cmd|
                expect(File.read(received_cmd)).to match(%r{.+/ssh hpc\.node /bin/bash <<'HPC_EOF'\n#{Regexp.escape(cmd)}\nHPC_EOF})
                [0, 'Bash commands executed on node', '']
              end
            ]
          ],
          expected_stdout: 'Bash commands executed on node'
        ) do
          # Use an argument that exceeds the max arg length limit
          test_connector.remote_bash(SecretString.new(cmd, silenced_str: '__INVALID_BASH__'))
        end
      end

      it 'copies files remotely with sudo' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{cd /path/to && tar\s+--create\s+--gzip\s+--file -\s+src.file \| /.+/ssh\s+hpc\.node\s+"sudo -u root tar\s+--extract\s+--gunzip\s+--file -\s+--directory /remote_path/to/dst.dir\s+--owner root\s+"},
              proc { [0, '', ''] }
            ]
          ]
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir', sudo: true)
        end
      end

      it 'copies files remotely with a different sudo' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{cd /path/to && tar\s+--create\s+--gzip\s+--file -\s+src.file \| /.+/ssh\s+hpc\.node\s+"other_sudo --user root tar\s+--extract\s+--gunzip\s+--file -\s+--directory /remote_path/to/dst.dir\s+--owner root\s+"},
              proc { [0, '', ''] }
            ]
          ],
          additional_config: <<~'EO_CONFIG'
            sudo_for { |user| "other_sudo --user #{user}" }
          EO_CONFIG
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir', sudo: true)
        end
      end

      it 'copies files remotely with a different owner' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{cd /path/to && tar\s+--create\s+--gzip\s+--file -\s+--owner remote_user\s+src.file \| /.+/ssh\s+hpc\.node\s+"tar\s+--extract\s+--gunzip\s+--file -\s+--directory /remote_path/to/dst.dir\s+--owner root\s+"},
              proc { [0, '', ''] }
            ]
          ]
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir', owner: 'remote_user')
        end
      end

      it 'copies files remotely with a different group' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{cd /path/to && tar\s+--create\s+--gzip\s+--file -\s+--group remote_group\s+src.file \| /.+/ssh\s+hpc\.node\s+"tar\s+--extract\s+--gunzip\s+--file -\s+--directory /remote_path/to/dst.dir\s+--owner root\s+"},
              proc { [0, '', ''] }
            ]
          ]
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir', group: 'remote_group')
        end
      end

      it 'executes bash commands remotely without Session Exec capabilities' do
        with_test_platform_for_remote_testing(
          expected_cmds: [[%r{^\{ cat \| .+/ssh hpc\.node -T; \} <<'HPC_EOF'\nbash_cmd.bash\nHPC_EOF$}, proc { [0, 'Bash commands executed on node', ''] }]],
          expected_stdout: 'Bash commands executed on node',
          session_exec: false
        ) do
          test_connector.remote_bash('bash_cmd.bash')
        end
      end

      it 'executes bash commands remotely without Session Exec capabilities using a SecretString' do
        with_test_platform_for_remote_testing(
          expected_cmds: [[%r{^\{ cat \| .+/ssh hpc\.node -T; \} <<'HPC_EOF'\nbash_cmd.bash\nHPC_EOF$}, proc { [0, 'Bash commands executed on node', ''] }]],
          expected_stdout: 'Bash commands executed on node',
          session_exec: false
        ) do
          test_connector.remote_bash(SecretString.new('bash_cmd.bash', silenced_str: '__INVALID_BASH__'))
        end
      end

      it 'copies files remotely without Session Exec capabilities' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [
              %r{^scp -S .+/ssh /path/to/src.file hpc\.node:/remote_path/to/dst.dir$},
              proc { [0, '', ''] }
            ]
          ],
          session_exec: false
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir')
        end
      end

      it 'copies files remotely without Session Exec capabilities and with sudo' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [%r{^\{ cat \| .+/ssh hpc\.node -T; \} <<'HPC_EOF'\nmkdir -p hpc_tmp_scp\nHPC_EOF$}, proc { [0, '', ''] }],
            [
              %r{^scp -S .+/ssh /path/to/src.file hpc\.node:\./hpc_tmp_scp$},
              proc { [0, '', ''] }
            ],
            [%r{^\{ cat \| .+/ssh hpc\.node -T; \} <<'HPC_EOF'\nsudo -u root mv \./hpc_tmp_scp/src\.file /remote_path/to/dst\.dir\nHPC_EOF$}, proc { [0, '', ''] }]
          ],
          session_exec: false
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir', sudo: true)
        end
      end

      it 'copies files remotely without Session Exec capabilities and with a different sudo' do
        with_test_platform_for_remote_testing(
          expected_cmds: [
            [%r{^\{ cat \| .+/ssh hpc\.node -T; \} <<'HPC_EOF'\nmkdir -p hpc_tmp_scp\nHPC_EOF$}, proc { [0, '', ''] }],
            [
              %r{^scp -S .+/ssh /path/to/src.file hpc\.node:\./hpc_tmp_scp$},
              proc { [0, '', ''] }
            ],
            [%r{^\{ cat \| .+/ssh hpc\.node -T; \} <<'HPC_EOF'\nother_sudo --user root mv \./hpc_tmp_scp/src\.file /remote_path/to/dst\.dir\nHPC_EOF$}, proc { [0, '', ''] }]
          ],
          additional_config: <<~'EO_CONFIG',
            sudo_for { |user| "other_sudo --user #{user}" }
          EO_CONFIG
          session_exec: false
        ) do
          test_connector.remote_copy('/path/to/src.file', '/remote_path/to/dst.dir', sudo: true)
        end
      end

    end

  end

end
