path = require 'path'
fs = require 'fs-plus'
rjson = require "relaxed-json"
process = require 'child_process'
byline = require 'byline'
git = require 'git-utils'
{MessagePanelView, PlainMessageView} = require 'atom-message-panel'

module.exports =
  activate: ->
    atom.commands.add "atom-text-editor",
      "secure-copy:upload-current-file": => @upload_current_file()
    atom.commands.add "atom-text-editor",
      "secure-copy:upload-git-changed": => @upload_git_changed()

    @messages = new MessagePanelView title: '<span class="icon-terminal"></span> Secure Copy', rawTitle: true

  find_sftp_config: (file) ->
    dirname = path.dirname(file)
    count = 0
    while (dirname != "/" && !fs.existsSync(path.join(dirname, 'sftp-config.json')))
      dirname = path.dirname(dirname)

    if dirname != "/"
      return dirname

    @messages.add new PlainMessageView message: "No sftp-config.json found. Check the README.", className: "text-warning"
    return null

  read_config: (filename) ->
    contents = fs.readFileSync(filename, 'utf-8')
    return RJSON.parse(contents)

  hideMessages: ->
    tearDown = =>
      @messages.hide()
      @messages.clear()
    clearTimeout @timer if @timer
    @timer = setTimeout tearDown, 3000

  updateMessage: (view, message) ->
    view.message = message
    view.html message
    @messages.summary.html message

  do_upload: (config, localFile, remoteFile, callback) ->
    # TODO: mkdir -p the destination first
    cmd = "/usr/bin/scp"
    if config.host
      params = [localFile, "#{config.user}@#{config.host}:#{remoteFile}"]
    else:
      params = [localFile, remoteFile]
    proc = process.spawn cmd, params
    all_output = []
    output = byline(proc.stderr)
    output.on 'data', (line) ->
      line = line.toString()
      all_output.push(line)
    proc.on 'exit', (exit_code, signal) ->
      callback exit_code, all_output

  processFiles: (files) ->
    fileToUpload = files.shift()
    if !@configDir
      @configDir = @find_sftp_config(fileToUpload)
    if @configDir
      if !@config
        @config = @read_config(path.join(@configDir, 'sftp-config.json'))
      relativeFile = fileToUpload.substring(@configDir.length + 1)
      remoteFile = path.join(@config.remote_path, fileToUpload.substring(@configDir.length))

      fileStatus = new PlainMessageView message: "Uploading #{relativeFile}... "
      @messages.add fileStatus
      @messages.body.scrollTop(@messages.body.height())
      @do_upload @config, fileToUpload, remoteFile, (exit_code, output) =>
        if exit_code
          # for line in output
          #   messages.add new PlainMessageView message: line
          @updateMessage fileStatus, "Uploading #{relativeFile}... <span class='text-error'>failed!</span>"
        else
          @updateMessage fileStatus, "Uploading #{relativeFile}... <span class='text-success'>success!</span>"

        if files.length
          @processFiles(files)
        else
          @hideMessages()

  upload_current_file: ->
    @messages.show()
    @messages.attach()
    @upload [atom.workspace.getActiveTextEditor().getPath()]

  upload: (filesToUpload) ->
    @processFiles(filesToUpload)

  upload_git_changed: ->
    @messages.show()
    @messages.attach()

    repos = atom.project.getRepositories()
    for idx, repo of repos
      toUpload = []
      repo = git.open(repo.getWorkingDirectory())
      for filePath, status of repo.getStatus()
        if !repo.isStatusModified(status)
          continue

        fullFilePath = path.join(repo.getWorkingDirectory(), filePath)

        if repo.isIgnored(fullFilePath)
        else
          if fs.isFileSync(fullFilePath)
            toUpload.push(fullFilePath)

      if toUpload.length
        @upload toUpload
      else
        @messages.add new PlainMessageView message: "No files to upload.", className: "text-warning"
        @hideMessages()

    if not repos.length
      @messages.add new PlainMessageView message: "No git repos for the current project.", className: "text-warning"
      @hideMessages()
