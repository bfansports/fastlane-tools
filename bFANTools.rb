require 'aws-sdk-ssm'
require 'aws-sdk-s3'
require 'aws-sdk-dynamodb'
require 'fastlane'
unless defined?(UI)
  UI = FastlaneCore::UI
end
require 'open-uri'
# Check if object is falsey
require "active_support/core_ext/object/blank"

###
### CUSTOM FUNCTIONS to be used with Android and iOS Fastfiles
### See their Fastfile for more information
###

###
# XXX SAVE : OLD VERSION PULLING FROM S3
###
# Get the current version of the Code and bump it
# def getVersionCode(file)
#   begin
#     s3 = Aws::S3::Client.new(region: 'us-east-1')
#     obj = s3.get_object({
#       bucket: "sportarchive-prod-creds",
#       key: 'android-versioncode/' + file,
#     })

#     # Get last version code and increment it
#     versionCode = obj.body.read.to_i
#     versionCode = versionCode + 1
#   rescue StandardError => msg
#     # display the system generated error message
#     puts msg
#     puts "VersionCode file: '" + file + "' doesn't exists. Creating it ..."
#     versionCode = 1
#     writeVersionCode(file, versionCode)
#   end

#   return versionCode
# end
###
###

# Load the proper configuration file
def loadAndroidConfigFile(org_id)
  json_key = "./json_keys/generic-api.json"
  if File.file?("#{Dir.pwd}/json_keys/#{org_id}-api.json")
    json_key = "./json_keys/#{org_id}-api.json"
  end
  UI.important("JSON_KEY used for Google API authentication: #{json_key}")

  return json_key
end

# Load the proper configuration file
def loadIOSConfigFile(org_id)
  file = "generic.yaml" # points to bFAN Sports config
  path = "./fastlane/"

  if File.exist?("FastlaneEnv")
    path = ""
  end

  # Is there is a config for the target ?
  if File.file?("#{path}./FastlaneEnv/#{org_id}.yaml")
    file = "#{org_id}.yaml"
  end

  conf = YAML.safe_load(File.read("#{path}./FastlaneEnv/#{file}"))

  UI.important("Config used: fastlane/FastlaneEnv/#{file}")

  return conf
end

# Reset changed file after a build
def resetIOSRepo
  # sh "git checkout -q bFan-ios-dev/bfan-ios-qa-Info.plist bFan-ios-dev/bfan-ios-prod-Info.plist bFan-ios-dev/bfan-ios-dev-Info.plist bFanUITest/Info.plist"
end

def getVersionCode(org_id, track)
  begin
    versionCode = 1
    versionCodeBeta = 1
    json_key = loadAndroidConfigFile(org_id)

    conf = JSON.parse(File.read(json_key))
    bundle_id = "com.bfansports.#{org_id}.prod"
    if conf.key?('bundle_id') && !conf['bundle_id'].nil?
      bundle_id = conf['bundle_id']
    end

    UI.important("bundle_id: #{bundle_id}")

    json_key = "./fastlane/#{json_key}"
    versioncodes = google_play_track_version_codes(
      package_name: bundle_id,
      track: track,
      json_key: json_key
    )
    if versioncodes.length > 0
      versionCode = (versioncodes[-1].to_i + 1).to_s
    end

    if track == 'beta'
      # Check production version code to make sure it's not less than beta
      versioncodes_prod = google_play_track_version_codes(
        package_name: bundle_id,
        track: "production",
        json_key: json_key
      )

      if versioncodes_prod.length > 0
        versionCodeProd = (versioncodes_prod[-1].to_i + 1).to_s
      end

      # If track prod > track beta
      if (versioncodes_prod[-1].to_i + 1) > (versioncodes[-1].to_i + 1)
        versionCode = versionCodeProd
      end
    end
  rescue StandardError => e
    begin
      versioncodes = google_play_track_version_codes(
        package_name: bundle_id,
        track: "production",
        json_key: json_key
      )
      if versioncodes.length > 0
        versionCode = (versioncodes[-1].to_i + 1).to_s
      else
        versionCode = 1
      end
    rescue StandardError => msg
      puts(msg)
    end
  end

  return versionCode
end

# Write the version Code file on disk
def writeVersionCode(file, versionCode)
  s3 = Aws::S3::Client.new(region: 'us-east-1')
  obj = s3.put_object({
    body: versionCode.to_s,
    bucket: "sportarchive-prod-creds",
    key: "android-versioncode/#{file}"
  })
end

# Get testers list (String separated by commas)
def getTestersList(org_id)
  begin
    UI.message("Getting s3://sportarchive-prod-creds/bfan_testers_list.txt")
    s3 = Aws::S3::Client.new(region: 'us-east-1')
    obj = s3.get_object({
      bucket: "sportarchive-prod-creds",
      key: 'bfan_testers_list.txt'
    },
                        target: '/tmp/bfan_testers_list.txt')
  rescue StandardError => e
    UI.error("Unable to get testers list from S3 from s3://sportarchive-prod-creds/bfan_testers_list.txt ")
    return ""
  end

  testers = File.read('/tmp/bfan_testers_list.txt').split(",")

  org = getOrg(org_id)
  if org && org['settings'] && org['settings']['apps'] && org['settings']['apps']['testers']
    UI.message("Adding custom testers: #{org['settings']['apps']['testers'].join(',')}")
    testers |= org['settings']['apps']['testers']
  end

  testers = testers.compact.reject(&:empty?).map!(&:strip)
  testers = testers.join(',')
  UI.important("Testers: #{testers}")

  return testers
end

# Get testers list
def getiPhonesList
  begin
    UI.message("Getting s3://sportarchive-prod-creds/bfan_iphones_list.json")
    s3 = Aws::S3::Client.new(region: 'us-east-1')
    obj = s3.get_object({
      bucket: "sportarchive-prod-creds",
      key: 'bfan_iphones_list.json'
    },
                        target: '/tmp/bfan_iphones_list.json')
  rescue StandardError => e
    UI.error("Unable to get iPhones list from S3 from s3://sportarchive-prod-creds/bfan_iphones_list.json")
    return []
  end

  iphones = JSON.parse(File.read('/tmp/bfan_iphones_list.json'))

  return iphones
end

def hotfixstart(tag)
  `git fetch --multiple origin`
  `git checkout develop`
  `git pull -f -q origin develop`
  `git checkout master`
  `git pull -f -q origin master`
  UI.important("[info] Creating a new hotfix branch #{tag}")
  `git checkout -b fastlane/#{tag} master`
end

def hotfixfinish(tag)
  `git checkout master`
  `git pull -f -q origin master`
  `git checkout fastlane/#{tag}`
  UI.important("[info] Rebasing your branch #{tag} on 'master'")
  `git rebase master`
  UI.important("[info] Merging your branch #{tag} in 'master' and 'develop'")
  `git checkout develop`
  `git pull -f -q origin develop`
  `git merge --no-ff -m "[skip ci] [fastlane] images_updates #{tag}" fastlane/#{tag}`
  `git checkout master`
  `git merge --no-ff -m "[skip ci] [fastlane] images_updates #{tag}" fastlane/#{tag}`
  UI.important("[info] Deleting old #{tag} branch")
  `git branch -D fastlane/#{tag}`
  `git tag -a #{tag} -m "[fastlane] Tag: #{tag}"`
end

def tagpush(tag)
  `git checkout master`
  UI.important("[info] Pushing master to origin")
  `git push origin master`
  UI.important("[info] Pushing new tag #{tag}")
  `git push origin #{tag}`
  `git checkout develop`
  UI.important("[info] Pushing develop to origin")
  `git push origin develop`
end

# Download org image assets into local folder
def downloadOrgImages(org_id, folder, asset_path)
  org = getOrg(org_id)

  unless org
    raise("No org #{org_id} in the database! Abording.")
  end

  `mkdir -p #{folder}`

  unless asset_path.nil?
    UI.important("asset_path provided. Inspecting path: #{asset_path}")
    if File.file?("#{asset_path}/ic_launcher.png")
      sh("convert #{asset_path}/ic_launcher.png -resize 512x512 #{folder}/store_icon_android.png")
      sh("convert #{asset_path}/ic_launcher.png #{folder}/store_icon_ios.jpg")
      return
    end
  end

  UI.important("Downloading images into #{folder}")
  # Splash
  if org['branding'] && org['branding']['splash_screen']
    UI.important("splash_screen")
    File.binwrite("#{folder}/splash_image.jpg", URI.open(org['branding']['splash_screen']).read)
  end

  # Launcher
  if org['branding'] && org['branding']['android_launch_icon']
    UI.important("android_launch_icon")
    File.binwrite("#{folder}/android_launch_icon.png", URI.open(org['branding']['android_launch_icon']).read)
  end
  if org['branding'] && org['branding']['ios_launch_icon']
    UI.important("ios_launch_icon")
    File.binwrite("#{folder}/ios_launch_icon.png", URI.open(org['branding']['ios_launch_icon']).read)
  end

  # Notifications
  if org['branding'] && org['branding']['notification_icon']
    UI.important("notification_icon")
    File.binwrite("#{folder}/notification_icon.png", URI.open(org['branding']['notification_icon']).read)
  end

  # Store icon
  if org['branding'] && org['branding']['store_icon']
    UI.important("store_icon")
    File.binwrite("#{folder}/store_icon.png", URI.open(org['branding']['store_icon']).read)
  end
  # Store icon android
  if org['branding'] && org['branding']['store_icon_android']
    UI.important("store_icon_android")
    File.binwrite("#{folder}/store_icon_android.png", URI.open(org['branding']['store_icon_android']).read)
  end
  # Store icon ios
  if org['branding'] && org['branding']['store_icon_ios']
    UI.important("store_icon_ios")
    File.binwrite("#{folder}/store_icon_ios.jpg", URI.open(org['branding']['store_icon_ios']).read)
  end
end

# Download org image assets into local folder
def downloadOrgAppIcon(org_id, folder)
    org = getOrg(org_id)

    unless org
      raise("No org #{org_id} found in the database! Aborting...")
    end

    `mkdir -p #{folder}`

    UI.important("Downloading images into #{folder}")
    # Launcher
    if org['branding'] && org['branding']['android_launch_icon']
      UI.important("android_launch_icon")
      File.binwrite("#{folder}/android_launch_icon.png", URI.open(org['branding']['android_launch_icon']).read)
    end
    if org['branding'] && org['branding']['ios_launch_icon']
      UI.important("ios_launch_icon")
      File.binwrite("#{folder}/ios_launch_icon.png", URI.open(org['branding']['ios_launch_icon']).read)
    end
  end

# Get the commit descs between the two latest tags
def getPastTagLogs(past1 = 1, past2 = 2, filter = true)
  # only return git logs that don't contain fastlane or private
  # use those keywords for your commit to be stealth in the build change logs
  to_exec = "git log --oneline #{past1}...#{past2}"
  if filter == true
    to_exec += " | { egrep -vi 'fastlane|skip_ci|Merge' || true; }"
  end
  changes = sh(to_exec)
  changes = changes[0...12_000]

  f = File.new("./tmp/changelog.txt", "w")
  f.write(changes)
  f.close

  UI.important("CHANGES SINCE LAST PROD: ")
  UI.important(changes)

  return changes
end

# Get Team ID from config file in fastlane/FastlaneEnv folder
def getTeamId(org_id)
  conf = loadIOSConfigFile(org_id)
  return conf['team_id']
end

# Get Team NAME from config file in fastlane/FastlaneEnv folder
def getTeamName(org_id)
  conf = loadIOSConfigFile(org_id)
  return conf['team_name']
end

# Get Git Branch NAME from config file in fastlane/FastlaneEnv folder
def getMatchGitBranch(org_id)
  conf = loadIOSConfigFile(org_id)
  return conf['match_git_branch']
end

# Get Team ID from config file in fastlane/FastlaneEnv folder
def getEnvVar
  if ENV['ENV'].nil?
    UI.user_error!("No 'ENV' environment variable set. Set it using `awsenv` config file. Must contain 'dev', 'qa' or 'prod' in value.")
  end

  env_raw = /(dev|qa|prod)/.match(ENV.fetch('ENV', nil))[1]
  UI.important("ENVIRONMENT: #{env_raw}")

  if env_raw.nil? || env_raw.length == 0
    UI.user_error!("Your 'ENV' environment variable is set but doesn't contain 'dev', 'qa' or 'prod' as value.")
  end

  return env_raw
end

# Fetch from upstream, or origin if no upstream
def getMainGitRemote
  remotes = sh("git remote", log: false).split
  if remotes.include?("upstream")
    return "upstream"
  else
    return "origin"
  end
end

# Get past gitTag. 'back' is how many tags back you want to go
def getPastGitTag(back = 1)
  remote = getMainGitRemote
  tags = sh("git ls-remote --tags --quiet #{remote} | cut -d '/' -f3", log: false).split
  semver_tags = tags.grep(/^[0-9]+.[0-9]+.[0-9]+$/) # only keep semver tags
  sorted_semver_tags = semver_tags.sort_by { |tag| Gem::Version.new(tag) }.reverse # sort by semver
  return sorted_semver_tags[back - 1]
end

# Get Commit ID for a specific tag
def getTagCommitId(tag)
  return sh("git rev-list -n 1 #{tag}")
end

# get last commit
def getLastCommit
  return sh("git rev-parse HEAD | tr -d '\n'")
end

# Get last remote
def getLastGitRemote
  return sh("git remote | tail -1 | tr -d '\n'")
end

# Get TAG associated to a release
def getReleaseTag(release)
  return sh("git rev-parse qa | xargs git tag --points-at | egrep -v 'qa|prod' | tr -d '\n'")
end

# Push to all remotes
def pushToGitRemotes(branch = 'develop', force = 0)
  if force
    force = "-f"
  else
    force = ""
  end
  remotes = `git remote`.split("\n")
  remotes.each do |remote|
    remote.chomp!
    UI.important("Pushing #{branch} to remote: #{branch}\"")
    sh("git push #{force} #{remote} #{branch}")
  end
end

# Pull from all remotes
def pullFromGitRemotes(branch)
  remotes = `git remote`.split("\n")
  remotes.each do |remote|
    remote.chomp!
    UI.important("Pulling #{branch} from remote: #{branch}\"")
    sh("git pull --no-edit #{remote} #{branch}")
  end
end

# gitCommit
def gitCommit(file, msg)
  sh("git diff-index --quiet HEAD -- #{file} || git commit #{file} -m '#{msg}'")
end

# Create Google Play changelog file
def createAndroidChangeLogFile(versionCode, org, release_notes)
  UI.important("Setting up changelogs: #{versionCode}.txt - #{org}")
  Dir.foreach(Dir.pwd + "/metadata/#{org}/") do |local|
    next if (local == '.') || (local == '..')

    if Dir.exist?(Dir.pwd + "/changelogs/#{local}")
      UI.important("Folder exists: #{local}. Copying ...")
      FileUtils.mkdir_p(Dir.pwd + "/metadata/#{org}/#{local}/changelogs")
      FileUtils.cp(Dir.pwd + "/changelogs/#{local}/changelog_template.txt",
                   Dir.pwd + "/metadata/#{org}/#{local}/changelogs/#{versionCode}.txt")
      open(Dir.pwd + "/metadata/#{org}/#{local}/changelogs/#{versionCode}.txt", 'a') do |f|
        f.puts(release_notes)
      end
    end
  end
rescue StandardError => e
  # display the system generated error message
  puts(e)
end

# Create Google Play changelog file
def createiOSChangeLogFile(org, release_notes)
  UI.important("Setting up changelogs: #{org}")
  Dir.foreach(Dir.pwd + "/metadata/#{org}/") do |local|
    next if (local == '.') || (local == '..')

    if Dir.exist?(Dir.pwd + "/changelogs/#{local}")
      UI.important("Folder exists: #{local}. Copying ...")
      FileUtils.cp(Dir.pwd + "/changelogs/#{local}/changelog_template.txt",
                   Dir.pwd + "/metadata/#{org}/#{local}/release_notes.txt")
      open(Dir.pwd + "/metadata/#{org}/#{local}/release_notes.txt", 'a') do |f|
        f.puts(release_notes)
      end
    end
  end
rescue StandardError => e
  # display the system generated error message
  puts(e)
end

# Get the next tag version
def getNextTagVersion
  current = sh("git fetch -q -f --all --tags > /dev/null 2>&1 && git tag -l | sort -n -t. -k1,1 -k2,2 -k3,3 -r | egrep -v 'qa|prod' | head -1 | tail -1 | tr -d '\n'")
  chunks = current.split('.')
  chunks[2] = chunks[2].to_i + 1

  return "#{chunks[0]}.#{chunks[1]}.#{chunks[2]}"
end

# Setup react dependencies
# def buildReact(react_tag, env, platform)
#   UI.important "Starting to build React bundle"
#   sh "cd ../../ && git checkout #{react_tag} && ./node-modules.sh && yarn deployment:#{platform}-#{env} && cd -"
# end

# Create keystore for the new app
def createKeystore(org)
  pwd = Dir.pwd
  keystore = `#{pwd}/keystore_generator.sh #{org}`
  return keystore
end

# Get AVD emulator
def getAvdEmulator
  avd = `emulator -list-avds | head -1 | tr -d '\n'`

  unless avd
    UI.error("You don't have any AVD setup. Please install android studio and start `android` command. Install the `emulator` command and ensure you create at least one AVD. Check online!")
    exit(1)
  end

  return avd
end

# Register app in crashlitics. Start it in emulator
# org_id:<org ID> and optional env:<dev|qa|prod>
def register_app(apk, bundle_id, env = "dev")
  if apk.nil?
    UI.error("Specify the APK you want to run and register in crashlytics. Provide the filename only, not the full path.")
    exit(1)
  end

  if bundle_id.nil?
    UI.error("Specify the bundle_id of the app you want to run and register in crashlytics.")
    exit(1)
  end

  avd = getAvdEmulator

  # Register the app in crashlytics by starting it
  sh("./register.sh #{apk} #{bundle_id} #{avd} #{env}")
end

# Update ios/android app active flag in org
def updateAppFlag(org_id, type, env, value)
  dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

  response = dynamodb.update_item(
    {
      table_name: "Organizations",
      key: {
        "id" => org_id
      },
      expression_attribute_names: {
        "#SETTINGS" => "settings",
        "#APPS" => "apps",
        "#TYPE" => type,
        "#ENV"  => env
      },
      expression_attribute_values: {
        ":value" => value
      },
      update_expression: "SET #SETTINGS.#APPS.#TYPE.#ENV = :value"
    }
  )

  return true
rescue Aws::DynamoDB::Errors::ServiceError => e
  UI.error(e.message)
  return false
end

# Update app version value in org
def updateAppBetaVersion(org_id, type, env, version)
  dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

  begin
    # Making sure "settings.apps is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps"
        },
        expression_attribute_values: {
          ":null" => nil,
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS = :empty",
        condition_expression: "#SETTINGS.#APPS = :null"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps' in org object")
  end

  begin
    # Making sure "settings.apps.type is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps",
          "#TYPE" => type
        },
        expression_attribute_values: {
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS.#TYPE =  if_not_exists(#SETTINGS.#APPS.#TYPE, :empty)"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps.#{type}' in org object")
  end

  # updating the values
  response = dynamodb.update_item(
    {
      table_name: "Organizations",
      key: {
        "id" => org_id
      },
      expression_attribute_names: {
        "#SETTINGS" => "settings",
        "#APPS" => "apps",
        "#TYPE" => type,
        "#ENV"  => env,
        "#ENV_VERSION" => "#{env}_version",
        "#ENV_DATE" => "#{env}_version_date"
      },
      expression_attribute_values: {
        ":env" => true,
        ":version" => version,
        ":date"    => Time.now.strftime("%d/%m/%Y")
      },
      update_expression: "SET #SETTINGS.#APPS.#TYPE.#ENV = :env," \
                         "#SETTINGS.#APPS.#TYPE.#ENV_VERSION = :version," \
                         "#SETTINGS.#APPS.#TYPE.#ENV_DATE = :date"
    }
  )

  return true
rescue Aws::DynamoDB::Errors::ServiceError => e
  UI.error(e.message)
  return false
end

# Update app in_store flag in org
def updateAppProdVersion(org_id, type, version)
  dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

  begin
    # Making sure "settings.apps is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps"
        },
        expression_attribute_values: {
          ":null" => nil,
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS = :empty",
        condition_expression: "#SETTINGS.#APPS = :null"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps' in org object")
  end

  begin
    # Making sure "settings.apps.{type} is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps",
          "#TYPE" => type
        },
        expression_attribute_values: {
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS.#TYPE =  if_not_exists(#SETTINGS.#APPS.#TYPE, :empty)"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps.#{type}' in org object")
  end

  # Setting the dates
  response = dynamodb.update_item(
    {
      table_name: "Organizations",
      key: {
        "id" => org_id
      },
      expression_attribute_names: {
        "#SETTINGS" => "settings",
        "#IN_STORE" => "in_stores",
        "#APPS" => "apps",
        "#TYPE" => type,
        "#ENV"  => "prod",
        "#STORE_VERSION" => "store_version",
        "#STORE_DATE" => "store_version_date",
        "#VERSION_IN_REVIEW" => "version_in_review",
        "#VERSION_IN_REVIEW_DATE" => "version_in_review_date"
      },
      expression_attribute_values: {
        ":env" => true,
        ":store" => true,
        ":version" => version,
        ":date" => Time.now.strftime("%d/%m/%Y"),
        ":null" => nil
      },
      update_expression: "SET #SETTINGS.#IN_STORE = :store," \
                         "#SETTINGS.#APPS.#TYPE.#ENV = :env," \
                         "#SETTINGS.#APPS.#TYPE.#STORE_VERSION = :version," \
                         "#SETTINGS.#APPS.#TYPE.#STORE_DATE = :date," \
                         "#SETTINGS.#APPS.#TYPE.#VERSION_IN_REVIEW = :null," \
                         "#SETTINGS.#APPS.#TYPE.#VERSION_IN_REVIEW_DATE = :null"
    }
  )

  return true
rescue Aws::DynamoDB::Errors::ServiceError => e
  UI.error(e.message)
  return false
end

# Update app in_store flag in org
def updateAppInReviewVersion(org_id, type, version)
  dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

  begin
    # Making sure "settings.apps is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps"
        },
        expression_attribute_values: {
          ":null" => nil,
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS = :empty",
        condition_expression: "#SETTINGS.#APPS = :null"
      }
    )
  rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException => e
    # ignore
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.error(e.message)
  end

  begin
    # Making sure "settings.apps.{type} is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps",
          "#TYPE" => type
        },
        expression_attribute_values: {
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS.#TYPE =  if_not_exists(#SETTINGS.#APPS.#TYPE, :empty)"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.error(e.message)
  end

  # Setting the dates
  response = dynamodb.update_item(
    {
      table_name: "Organizations",
      key: {
        "id" => org_id
      },
      expression_attribute_names: {
        "#SETTINGS" => "settings",
        "#APPS" => "apps",
        "#TYPE" => type,
        "#ENV"  => "prod",
        "#VERSION_IN_REVIEW" => "version_in_review",
        "#VERSION_IN_REVIEW_DATE" => "version_in_review_date"
      },
      expression_attribute_values: {
        ":env" => true,
        ":version" => version,
        ":date" => Time.now.strftime("%d/%m/%Y")
      },
      update_expression: "SET #SETTINGS.#APPS.#TYPE.#ENV = :env," \
                         "#SETTINGS.#APPS.#TYPE.#VERSION_IN_REVIEW = :version," \
                         "#SETTINGS.#APPS.#TYPE.#VERSION_IN_REVIEW_DATE = :date"
    }
  )

  return true
rescue Aws::DynamoDB::Errors::ServiceError => e
  UI.error(e.message)
  return false
end

# Update the state of the store version in org
def updateAppStoreState(org_id, type, version)
  dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

  begin
    # Making sure "settings.apps is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps"
        },
        expression_attribute_values: {
          ":null" => nil,
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS = :empty",
        condition_expression: "#SETTINGS.#APPS = :null"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps' in org object")
  end

  begin
    # Making sure "settings.apps.{type} is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps",
          "#TYPE" => type
        },
        expression_attribute_values: {
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS.#TYPE =  if_not_exists(#SETTINGS.#APPS.#TYPE, :empty)"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps.#{type}' in org object")
  end

  # Setting the dates
  response = dynamodb.update_item(
    {
      table_name: "Organizations",
      key: {
        "id" => org_id
      },
      expression_attribute_names: {
        "#SETTINGS" => "settings",
        "#APPS" => "apps",
        "#TYPE" => type,
        "#STORE_VERSION" => "store_version",
        "#STORE_STATE" => "store_version_state"
      },
      expression_attribute_values: {
        ":version" => version.version_string,
        ":state" => version.app_store_state
      },
      update_expression: "SET " \
                         "#SETTINGS.#APPS.#TYPE.#STORE_VERSION = :version," \
                         "#SETTINGS.#APPS.#TYPE.#STORE_STATE = :state"
    }
  )

  return true
rescue Aws::DynamoDB::Errors::ServiceError => e
  UI.error(e.message)
  return false
end

# Update app ratings in org
def updateAppStoreRatings(org_id, type, ratings)
  dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

  begin
    # Making sure "settings.apps is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps"
        },
        expression_attribute_values: {
          ":null" => nil,
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS = :empty",
        condition_expression: "#SETTINGS.#APPS = :null"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps' in org object")
  end

  begin
    # Making sure "settings.apps.{type} is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps",
          "#TYPE" => type
        },
        expression_attribute_values: {
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS.#TYPE =  if_not_exists(#SETTINGS.#APPS.#TYPE, :empty)"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps.#{type}' in org object")
  end

  begin
    # Making sure "settings.apps.{type}.ratings is init correctly"
    response = dynamodb.update_item(
      {
        table_name: "Organizations",
        key: {
          "id" => org_id
        },
        expression_attribute_names: {
          "#SETTINGS" => "settings",
          "#APPS" => "apps",
          "#TYPE" => type,
          "#RATINGS" => "ratings"
        },
        expression_attribute_values: {
          ":empty" => {}
        },
        update_expression: "SET #SETTINGS.#APPS.#TYPE.#RATINGS =  if_not_exists(#SETTINGS.#APPS.#TYPE.#RATINGS, :empty)"
      }
    )
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.important("Skipping setting 'settings.apps.#{type}.ratings' in org object")
  end

  # Setting the reviews
  response = dynamodb.update_item(
    {
      table_name: "Organizations",
      key: {
        "id" => org_id
      },
      expression_attribute_names: {
        "#SETTINGS" => "settings",
        "#APPS" => "apps",
        "#TYPE" => type,
        "#RATINGS" => "ratings",
        "#RATING_COUNT" => "rating_count",
        "#AVERAGE_RATING" => "average_rating",
        "#ONE_STAR_RATING_COUNT"  => "one_star_rating_count",
        "#TWO_STAR_RATING_COUNT"  => "two_star_rating_count",
        "#THREE_STAR_RATING_COUNT" => "three_star_rating_count",
        "#FOUR_STAR_RATING_COUNT"  => "four_star_rating_count",
        "#FIVE_STAR_RATING_COUNT"  => "five_star_rating_count"
      },
      expression_attribute_values: {
        ":rating_count" => ratings.rating_count,
        ":average_rating" => ratings.average_rating,
        ":one_star_rating_count" => ratings.one_star_rating_count,
        ":two_star_rating_count" => ratings.two_star_rating_count,
        ":three_star_rating_count" => ratings.three_star_rating_count,
        ":four_star_rating_count" => ratings.four_star_rating_count,
        ":five_star_rating_count" => ratings.five_star_rating_count
      },
      update_expression: "SET " \
                         "#SETTINGS.#APPS.#TYPE.#RATINGS.#RATING_COUNT = :rating_count," \
                         "#SETTINGS.#APPS.#TYPE.#RATINGS.#AVERAGE_RATING = :average_rating," \
                         "#SETTINGS.#APPS.#TYPE.#RATINGS.#ONE_STAR_RATING_COUNT = :one_star_rating_count," \
                         "#SETTINGS.#APPS.#TYPE.#RATINGS.#TWO_STAR_RATING_COUNT = :two_star_rating_count," \
                         "#SETTINGS.#APPS.#TYPE.#RATINGS.#THREE_STAR_RATING_COUNT = :three_star_rating_count," \
                         "#SETTINGS.#APPS.#TYPE.#RATINGS.#FOUR_STAR_RATING_COUNT = :four_star_rating_count," \
                         "#SETTINGS.#APPS.#TYPE.#RATINGS.#FIVE_STAR_RATING_COUNT = :five_star_rating_count"
    }
  )

  return true
rescue Aws::DynamoDB::Errors::ServiceError => e
  UI.error(e.message)
  return false
end

# Return one org
def getOrg(org_id)
  dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

  response = dynamodb.get_item(
    {
      table_name: "Organizations",
      key: {
        "id" => org_id
      }
    }
  )

  return response.item
rescue Aws::DynamoDB::Errors::ServiceError => e
  UI.error(e.message)
  return nil
end

# Get active orgs from DynamoDB based on the "public" flag
def getActiveOrgs
  UI.important("Getting organization active organizations from DB")

  begin
    dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

    items = dynamodb_full_scan(dynamodb,
                               {
                                 table_name: "Organizations",
                                 projection_expression: "id, #SE, #ST",
                                 expression_attribute_names: {
                                   "#SE" => "settings",
                                   "#ST" => "status"
                                 },
                                 expression_attribute_values: {
                                   ":p" => "public",
                                   ":s" => true
                                 },
                                 filter_expression: "#ST.active = :s AND #SE.listing = :p"
                               })

    orgs = []
    UI.important("Organization to BUILD:")
    items.each do |item|
      orgs.push(item['id'])
      UI.important(item['id'])
    end

    return orgs
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.error(e.message)
    return nil
  end
end

# Get active orgs from DynamoDB based on the "in_stores" flag
def getInStoreOrgs
  UI.important("Getting organization active organizations from DB")

  begin
    dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

    items = dynamodb_full_scan(dynamodb,
                               {
                                 table_name: "Organizations",
                                 projection_expression: "id, #SE, #ST",
                                 expression_attribute_names: {
                                   "#SE" => "settings",
                                   "#ST" => "status"
                                 },
                                 expression_attribute_values: {
                                   ":p" => "public",
                                   ":s" => true
                                 },
                                 filter_expression: "#SE.in_stores = :s AND #SE.listing = :p"
                               })

    orgs = []
    UI.important("Organization to BUILD:")
    items.each do |item|
      next unless (item["status"]["active"] == true) && \
                  (item["id"] != "bfanteam")

      orgs.push(item["id"])
      UI.important(item["id"])
    end

    return orgs
  rescue Aws::DynamoDB::Errors::ServiceError => e
    UI.error(e.message)
    return nil
  end
end

def notifySlack(msg, payload, success, channel)
  slack_payload = {
      'Build Date' => Time.new.to_s,
      'Built by' => 'Fastlane',
      'Message' => payload
  }
  if ENV["BITRISE_BUILD_URL"]
    slack_payload['Bitrise URL'] = ENV["BITRISE_BUILD_URL"]
  end
  if ENV.key?("SLACK_BFAN_URL")
    slack(
      message: msg,
      success: success,
      slack_url: ENV["SLACK_BFAN_URL"],
      channel: channel,
      payload: slack_payload,
      default_payloads: []
    )
  else
    UI.error("SLACK_BFAN_URL not set")
    UI.error("Slack notification: #{msg}")
    UI.error("Slack payload: #{payload}")
  end
end

def notifySlackClient(msg, org_id)
  unless ENV.key?("SLACK_CLIENT_URL")
    UI.error("SLACK_CLIENT_URL not set")
    UI.error("Slack notification: #{msg}")
    return
  end
  # Check the database if the client channel is different from the org_id
  # For example org_id stadefrancais has a slack channel named "#stadefrançaisparis"
  org = getOrg(org_id)
  if org && org['integrations'] && org['integrations']['slack'] && org['integrations']['slack']['name']
    channel = "##{org['integrations']['slack']['name']}"
  else
    channel = "##{org_id}"
  end

  slack(
    message: msg,
    username: "bFAN AutoBuild Bot",
    icon_url: "https://sportarchive-prod-eu-assets.s3-eu-west-1.amazonaws.com/images/bFAN_circle_128sq_color.png",
    success: true,
    slack_url: ENV.fetch("SLACK_CLIENT_URL", nil),
    channel: channel,
    default_payloads: [],
    payload: {
      'Build Date' => Time.new.to_s
    }
  )
end

# Returns the ALL the items from dynamodb.scan instead of the 1 MB limit.
# https://gist.github.com/mmyoji/eafd3a6b7b5ef3569d1f6d4978fa0c64
def dynamodb_full_scan(dynamodb = Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil)), scan_opts)
  items = []
  scan_output = dynamodb.scan(scan_opts)

  loop do
    items << scan_output.items

    break unless (lek = scan_output.last_evaluated_key)

    scan_output = dynamodb.scan(scan_opts.merge(exclusive_start_key: lek))
  end

  return items.flatten
end

# Looks inside fastlane/metadata/#{org}/ for locale folders
# Used to detect the locales for screenshots
# @param [String] org organisation id
# @param [Array<String>] default_locales return value in case of an error
# @param [String] metadata_path custom path where the locale folders are located
# @return [Array<String>] list of locales
def get_locales_from_metadata(org, default_locales = [], metadata_path: "")
  locales = default_locales

  begin
    if metadata_path.blank?
      directory = "./metadata/#{org}/"
    else
      directory = metadata_path
    end
    locales = Dir.entries(directory).select { |entry| File.directory?(File.join(directory, entry)) and entry =~ /\D+-\D+/ }
  rescue SystemCallError => e
    # Directory does not exist.
    UI.error("#{e} (directory=#{directory})")
  end

  return locales
end

# Run after all
def afterAll(tag, env)
  UI.important("Updating git tracker for changelogs")
  # Save 'old'
  sh("git tag -f #{env} #{tag}")
  # Git Push-force (1) to ALL your Remotes
  pushToGitRemotes(env, 1)
end

# Get the React Tag for current project tag
# def getReactTag(tag)

#   # If tag is a tag and react_tag is null
#   # We the best react tag for our tag
#   if /^[0-9]*\.[0-9]*(\.[0-9]*)*$/.match(tag) != nil
#     # It's a tag, we split it and return it
#     chunks = tag.split('.')
#     # We get the closest react tag looking at the first two digits
#     matching = `cd ../.. && git tag -l | sort -n -t. -k1,1 -k2,2 -k3,3 -r | egrep '^#{chunks[0]}\.#{chunks[1]}' | egrep -v 'qa|prod' | head -1 | tail -1 | tr -d '\n' && cd - > /dev/null`
#     return matching
#   end

#   # We find an exact same branch in react
#   matching = `cd ../.. && git branch | grep #{tag} | head -1 | tail -1 | tr -d '\n' | tr -d ' ' | tr -d '*' && cd - > /dev/null`
#   if tag == matching
#     return matching
#   end

#     # If feature branch
#   if /^(feature)\/.+$/.match(tag) != nil
#     return 'develop'
#   end

#   # If hotfix or release branch
#   if /^(release|hotfix)\/.+$/.match(tag) != nil
#     return 'master'
#   end

#   return 'develop'
# end

# Run before all
def beforeAll(tag)
  UI.important("Setup git for the build")

  # get tag
  if tag.nil? || tag == "develop"
    # we get the last commit
    tag = "develop"
    UI.important("No TAG provided to build. Using the 'develop' latest commit: #{tag}")
  elsif tag == "master"
    # we get the last TAG
    tag = getPastGitTag
    UI.important("No TAG provided to build. Using the 'master' latest TAG: #{tag}")
  end

  remote = getMainGitRemote

  if /^[0-9]+\.[0-9]+(\.[0-9]*)*$/.match(tag).nil?
    # Fetch the branch in case it's a shallow clone
    sh("git fetch #{remote} #{tag}")
  else
    # Fetch the tag in case it's a shallow clone
    sh("git fetch #{remote} refs/tags/#{tag}:refs/tags/#{tag}")
  end

  # Checkout the tag or branch
  sh("pwd && git checkout #{tag}")

  # If it's not a tag, we pull the branch to get latest code
  if /^[0-9]+\.[0-9]+(\.[0-9]*)*$/.match(tag).nil?
    pullFromGitRemotes(tag)
  end

  UI.important("TAG: '#{tag}'")

  return tag
end

# Sets the firebase credentials in the environment for the current project
# Returns the path to the service account key file in case you need it
# @param [String] org_id organisation id
# @param [String] firebase_project_id firebase project id
# @return [String] path to the service account key file
def set_firebase_credentials(org_id: String, firebase_project_id: String)
  if firebase_project_id.nil?
    firebase_project_id = get_firebase_project_id(org_id)
  end
  if firebase_project_id.nil?
    return nil
  end

  ssm = Aws::SSM::Client.new
  begin
    # Get the Google Cloud credentials from SSM Parameter Store
    # and write them to a file
    ssm_response = ssm.get_parameter({
      name: "/google_cloud_ci_cd_service_account_generator/firebase_service_account_keys/#{firebase_project_id}",
      with_decryption: true
    })
    service_account_key = ssm_response.parameter.value
    service_account_key_file = File.expand_path("firebase_service_account_key.json")
    File.write(service_account_key_file, service_account_key)
    # Set the GOOGLE_APPLICATION_CREDENTIALS environment variable
    # so that the firebase-tools can use the credentials
    ENV["GOOGLE_APPLICATION_CREDENTIALS"] = service_account_key_file
    # Unset the deprecated FIREBASE_TOKEN environment variable
    ENV.delete("FIREBASE_TOKEN")
    return service_account_key_file
  rescue Aws::SSM::Errors::ServiceError => e
    UI.error("Unable to get Google Cloud credentials for firebase project '#{firebase_project_id}'")
    UI.error(e.message)
    return nil
  end
end

desc "Uploads the firebase hosting config to the specified firebase project"
desc "This is used to ensure that the dynamic links work"
desc "Usage: fastlane deploy_firebase_hosting [orgs:<org_id_1>,<org_id_2>,...] [all:true] [dry_run:true]"
desc "orgs: List of organisations (default: bfanteam)"
desc "all: Superseeds 'orgs' parameter. Will build all public orgs based on your AWS environment. (default: false)"
desc "dry_run: Doesn't deploy firebase hosting (used for testing) (default: false)"
desc "Note: You need firebase-tools (and Node.js) installed on your system,"
desc "and an admin $FIREBASE_TOKEN in your environment."
desc "To install firebase-tools, run `npm install -g firebase-tools`"
lane :deploy_firebase_hosting do |options|
  if options[:all].to_s.casecmp("true").zero?
    orgs = getActiveOrgs
  elsif options[:orgs]
    orgs = options[:orgs].split(",")
  else
    orgs = ['bfanteam']
  end

  orgs.each do |org|
    project_id = get_firebase_project_id(org)
    if project_id
      command = "cd firebase; firebase deploy --only hosting --project #{project_id}"
      if options[:dry_run].to_s.casecmp("true").zero?
        UI.important("DRY_RUN ENABLED skipping #{command}")
      else
        begin
          set_firebase_credentials(firebase_project_id: project_id)
          sh(command)
        rescue StandardError => e
          UI.error(e)
          UI.error("Firebase deploy failed for #{project_id}, skipping.")
          UI.error("The issue is probably that the Google Cloud credentials are not set up correctly.")
          UI.error("See https://github.com/bfansports/google_cloud_ci_cd_service_account_generator")
        end
      end
    else
      UI.error("Can't deploy Firebase Hosting for #{org}, no Project ID found.")
    end
  end
end
