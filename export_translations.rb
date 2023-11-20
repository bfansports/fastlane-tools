#!/usr/bin/env ruby

require 'aws-sdk-dynamodb'
require 'json'
require 'htmlentities'

### To run this script :
###   - android : ./export_translations.rb --os=android --path=/home/mathieu/dev/bfan/apps/SA-User-WhiteLabelApps-Android
###   - ios : ./export_translations.rb --os=ios --path=/home/mathieu/dev/bfan/apps/SA-User-MobileApp-iOS/

def export_translations(os, path)

    puts 'Starting export for ' + os + ' in the path ' + path

    $project_path = path

    if $project_path.end_with?("/") == false
        $project_path = $project_path + '/'
    end

    $export_os = os

    start_ts = get_milliseconds_timestamp()

    dynamo_client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION'))
    dynamo_resource = Aws::DynamoDB::Resource.new(client: dynamo_client)

    puts 'Fetching data from db'

    table_asm = dynamo_resource.table('AppStringsTranslations')
    translations = scan_table(table_asm, {})

    table_languages = dynamo_resource.table('Languages')
    languages = scan_table(table_languages, {})
    languages_lookup = build_languages_lookup(languages)

    default_translation_lookup = {}
    prepared = {}

    puts 'Prepare data'

    translations.each do |translation|
        if translation.fetch('org_id') == 'default'
            default_translation_lookup[ translation.fetch('gid') ] = translation
            if translation.fetch('translations') and translation['translations'].kind_of?(Array)
                translation['translations'].each do |lang_trans|
                    if translation['os_config'].fetch($export_os, nil) and translation['os_config'][$export_os].fetch('active', nil)
                        destination_file = get_global_file_destination($export_os, translation, lang_trans, languages_lookup)
                        if prepared.fetch( destination_file, nil ) == nil
                            prepared[ destination_file ] = []
                        end
                        data = get_translation_data($export_os, translation, lang_trans)
                        data.each do |line|
                            prepared[ destination_file ].append(line)
                        end
                    end
                end
            end
        end
    end

    translations.each do |translation|
        if translation.fetch('org_id') != 'default'
            ref_translation = default_translation_lookup.fetch(translation['gid'], nil)
            if ref_translation and translation.fetch('translations') and translation['translations'].kind_of?(Array)
                translation['translations'].each do |lang_trans|
                    if ref_translation['os_config'].fetch($export_os, nil) and ref_translation['os_config'][$export_os].fetch('active', nil)
                        destination_file = get_org_file_destination(translation.fetch('org_id'), $export_os, ref_translation, lang_trans, languages_lookup)
                        if prepared.fetch( destination_file, nil ) == nil
                            prepared[ destination_file ] = []
                        end
                        data = get_translation_data($export_os, ref_translation, lang_trans)
                        data.each do |line|
                            prepared[ destination_file ].append(line)
                        end
                    end
                end
            end
        end
    end

    if $export_os == 'ios'
        puts 'Cleaning existing iOS org files'
        ios_org_path = $project_path + 'bFan-ios-dev/Organizations/'
        entries = Dir.entries(ios_org_path)
        entries.each do |entry|
            dirname = File.dirname(entry)
            if dirname != '_EMPTY'
                languages.each do |language|
                    team_file_path = entry + '/' + language['os_locale']['ios'] + '.lproj/Team.strings'
                    if File.exist?(team_file_path)
                        File.delete(team_file_path)
                    end
                end
            end
        end
    elsif $export_os == 'android'
        puts 'Cleaning existing Android org files'
        android_org_path = $project_path + 'app/src/'
        entries = Dir.entries(android_org_path)
        entries.each do |entry|
            dirname = File.dirname(entry)
            if dirname != 'main'
                languages.each do |language|
                    team_file_path = entry + '/res/values-' + language['os_locale']['android'] + '/strings.xml'
                    if File.exist?(team_file_path)
                        File.delete(team_file_path)
                    end
                end
            end
        end
    end

    puts 'Writing data to files'

    if $export_os == 'ios'
        write_ios_files(prepared)
    elsif $export_os == 'android'
        write_android_files(prepared)
    end

    end_ts = get_milliseconds_timestamp()

    puts 'Export finished successfully in ' + ((end_ts.to_f - start_ts.to_f) / 1000 ).to_s + ' seconds'

end

def get_milliseconds_timestamp()
    return Time.now.strftime('%s%L')
end

def scan_table(table, params)
    items = []
    done = false
    start_key = nil
    until done
        params[:exclusive_start_key] = start_key unless start_key.nil?
        response = table.scan(params)
        items.concat(response.items) unless response.items.empty?
        start_key = response.last_evaluated_key
        done = start_key.nil?
    end
    return items
end

def build_languages_lookup(languages)
    lookup = {}
    languages.each do |language|
        lookup[ language.fetch('locale') ] = language
    end
    return lookup
end

def get_global_file_destination(os, translation, lang_data, languages_lookup)
    if os == 'android'
        return $project_path + 'app/src/main/res/values-' + languages_lookup[ lang_data['lang_code'] ]['os_locale'][ os ] + '/' + translation['os_config'][ os ]['file']
    elsif os == 'ios'
        return $project_path + 'bFan-ios-dev/Resources/' + languages_lookup[ lang_data['lang_code'] ]['os_locale'][ os ] + '.lproj/' + translation['os_config'][ os ]['file']
    else
        puts 'get_global_file_destination: No OS provided'
        exit()
    end
end

def get_org_file_destination(org_id, os, translation, lang_data, languages_lookup)
    if os == 'android'
        return $project_path + 'app/src/' + org_id + '/res/values-' + languages_lookup[ lang_data['lang_code'] ]['os_locale'][ os ] + '/' + translation['os_config'][ os ]['file']
    elsif os == 'ios'
        return $project_path + 'bFan-ios-dev/Organizations/' + org_id.upcase + '/' + languages_lookup[ lang_data['lang_code'] ]['os_locale'][ os ] + '.lproj/Team.strings'
    else
        puts 'get_org_file_destination: No OS provided'
        exit()
    end
end

def get_translation_data(os, translation, lang_data)
    data = []
    if os == 'android'
        if translation.fetch('plurals', nil) and translation['plurals'].fetch('active', false)
            if translation.fetch('os_config', nil) and translation['os_config'].fetch(os, nil) and translation['os_config'][ os ].fetch('app_key', nil)
                data.append(prepare_android_plural(
                    translation,
                    translation['os_config'][ os ].fetch('app_key'),
                    lang_data.fetch('lang_plurals'),
                    translation.fetch('use_cdata', false)
                ))
            end
            if translation.fetch('app_key', nil)
                data.append(prepare_android_plural(
                    translation,
                    translation.fetch('app_key'),
                    lang_data.fetch('lang_plurals'),
                    translation.fetch('use_cdata', false)
                ))
            end
        else
            if translation.fetch('os_config', nil) and translation['os_config'].fetch(os, nil) and translation['os_config'][ os ].fetch('app_key', nil)
                data.append(prepare_android_singular(
                    translation,
                    translation['os_config'][ os ].fetch('app_key'),
                    lang_data.fetch('lang_value'),
                    translation.fetch('use_cdata', false)
                ))
            end
            if translation.fetch('app_key', nil)
                data.append(prepare_android_singular(
                    translation,
                    translation.fetch('app_key'),
                    lang_data.fetch('lang_value'),
                    translation.fetch('use_cdata', false)
                ))
            end
        end
    elsif os == 'ios'
        if translation.fetch('os_config', nil) and translation['os_config'].fetch(os, nil) and translation['os_config'][ os ].fetch('app_key', nil)
            data.append(prepare_ios_string(
                translation['os_config'][ os ].fetch('app_key'),
                lang_data.fetch('lang_value')
            ))
        end
        if translation.fetch('app_key', nil)
            data.append(prepare_ios_string(
                translation.fetch('app_key'),
                lang_data.fetch('lang_value')
            ))
        end
    else
        puts 'get_translation_data: No OS provided'
        exit()
    end
    return data
end

def prepare_ios_string(app_key, value)
    return '"' + app_key + '" = "' + prepare_ios_value(value) + '";'
end

def prepare_ios_value(data)
    data = data.gsub("\n", "\\n")
    data = data.gsub(/["']/, '\\\\\0')
    data = data.gsub(/\[var_\d+\]/, '%@')
    return data
end

def prepare_android_plural(translation, app_key, value, use_cdata)
    plurals_options = []
    if use_cdata
        value.each do |val|
            plurals_options.append(
                '<item quantity="' + val['type'] + '"><![CDATA[ ' + prepare_android_value(translation, val['value'], use_cdata) + ' ]]></item>'
            )
        end
    else
        value.each do |val|
            plurals_options.append(
                '<item quantity="' + val['type'] + '">' + prepare_android_value(translation, val['value'], use_cdata) + '</item>'
            )
        end
    end
    return '<plurals name="' + app_key + '" tools:ignore="MissingQuantity,UnusedQuantity">' + plurals_options.join('') + '</plurals>'
end

def prepare_android_singular(translation, app_key, value, use_cdata)
    if use_cdata
        return '<string name="' + app_key + '"><![CDATA[ ' + prepare_android_value(translation, value, use_cdata) + ' ]]></string>'
    else
        return '<string name="' + app_key + '">' + prepare_android_value(translation, value, use_cdata) + '</string>'
    end
end

def prepare_android_value(translation, data, use_cdata)
    data = data.gsub("\n", "\\n")
    data = data.gsub(/["']/, '\\\\\0')
    if use_cdata == false
        data = HTMLEntities.new.encode(data)
    end
    vars = translation.fetch('var', nil)
    if vars
        vars.each_with_index do |val, idx|
            type_letter = 's'
            if val['type'] == 'number'
                type_letter = 'd'
            end
            data = data.gsub('[var_' + (idx + 1).to_s + ']', '%' + (idx + 1).to_s + '$' + type_letter)
        end
    end
    return data
end

def write_android_files(data)
    if $dry_run
        File.open('prepared-android.json', "w") do |file|
            file.write(JSON.generate(data))
        end
    else
        data.each do |filepath, lines|
            write_android_file(filepath, lines)
            if filepath.include?('/values-en/')
                filepath = filepath.gsub('values-en', 'values')
                write_android_file(filepath, lines)
            end
        end
    end
end

def write_android_file(filepath, lines)
    File.open(filepath, "w") do |file|
        current_time = Time.now
        formatted_time = current_time.strftime("%Y-%m-%d %H:%M:%S")

        ## sort line by the name attribute
        tmp_doc = Nokogiri::XML('<root>' + lines.join() + '</root>', &:noblanks)
        elements = tmp_doc.xpath('//*[@name]')
        sorted_elements = elements.sort_by { |elem| elem['name'] }
        items = []
        sorted_elements.each do |elem|
            items.append(elem.to_xml)
        end

        ## generate final file
        content = '<?xml version="1.0" encoding="utf-8"?>'
        content = content + "<!-- File generated on " + formatted_time + " -->"
        content = content + '<resources xmlns:tools="http://schemas.android.com/tools">' + items.join('') + '</resources>'
        doc_final = Nokogiri::XML(content, &:noblanks)
        doc_final.write_to(file, indent: 2, save_with: Nokogiri::XML::Node::SaveOptions::FORMAT)
    end
end

def write_ios_files(data)
    if $dry_run
        File.open('prepared-ios.json', "w") do |file|
            file.write(JSON.generate(data))
        end
    else
        data.each do |filepath, lines|
            File.open(filepath, "w") do |file|
                current_time = Time.now
                formatted_time = current_time.strftime("%Y-%m-%d %H:%M:%S")
                content = "// File generated on " + formatted_time + "\n"
                content = content + lines.sort.join("\n")
                file.write(content)
            end
        end
    end
end

def check_args(os, path)
    if os == nil
        puts 'Missing os parameter'
        exit()
    end
    if os != 'android' and os != 'ios'
        puts 'Os not supported (android/ios) : ' + os
        exit()
    end
    if path == nil
        puts 'Missing path parameter'
        exit()
    end
    if Dir.exist?(path) == false
        puts 'Path doesn\'t exists'
        exit()
    end
end

### Run the script

if __FILE__ == $PROGRAM_NAME
    $project_path = nil
    $export_os = nil
    $dry_run = false

    ARGV.each do |arg|
        case arg
        when /\A--help\z/
            puts 'Run the script : ./export.rb --os=android --path=/android-project-path/'
            exit()
        when /\A--dry-run\z/
            $dry_run = true
        when /\A--os=(.*)\z/
            $export_os = $1
        when /\A--path=(.*)\z/
            $project_path = $1
        end
    end

    check_args($export_os, $project_path)

    export_translations($export_os, $project_path)
end
