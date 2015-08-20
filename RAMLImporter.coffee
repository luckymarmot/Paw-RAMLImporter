require "yaml.min.js"

RAMLImporter = ->

    # Create Paw requests from a RAML Request (object)
    @createPawRequest = (context, ramlCollection, ramlRequestPath, ramlRequestMethod, ramlRequestValue) ->

        if ramlRequestValue.summary
          ramlRequestTitle = ramlRequestValue.summary
        else
          ramlRequestTitle = ramlRequestPath

        headers = {}
        queries = {}
        formData = {}
        body

        # Extract contentType from Consumes and add the first one to Headers
        if ramlRequestValue.consumes
          for contentType in ramlRequestValue.consumes
            headers["Content-Type"] = contentType
            break

        # Extract Headers and Query params
        for index, ramlRequestParamValue of ramlRequestValue.parameters

          # Add Queries
          if ramlRequestParamValue.in == 'query' and ramlRequestParamValue.type == 'string'
            queries[ramlRequestParamValue.name] = ramlRequestParamValue.name

          # Add Headers
          if ramlRequestParamValue.in == 'header' and ramlRequestParamValue.type == 'string'
            headers[ramlRequestParamValue.name] = ramlRequestParamValue.name

          # Add Url Encoded
          if ramlRequestParamValue.in == 'formData' and ramlRequestParamValue.type == 'string'
            formData[ramlRequestParamValue.name] = ramlRequestParamValue.name

          # Add Body
          if ramlRequestParamValue.in == 'body' #Only string
            body = @json_from_definition_schema ramlCollection, ramlRequestParamValue.schema

        ramlRequestUrl = @createRAMLRequestUrl ramlCollection, ramlRequestPath, queries
        ramlRequestMethod = ramlRequestMethod.toUpperCase()

        # Create Paw request
        pawRequest = context.createRequest ramlRequestTitle, ramlRequestMethod, ramlRequestUrl

        # Add Headers
        for key, value of headers
          pawRequest.setHeader key, value

        # Add Basic Auth if required
        pawRequest.setHeader "Authorization", "HTTP Basic Auth (Username/Password)" if @has_basic_auth ramlCollection, ramlRequestValue

        # Set raw body
        pawRequest.body = body if body

        # Set Form URL-Encoded body
        if Object.keys(formData).length > 0
            # Set Form URL-Encoded body
            if headers['Content-Type'] == "application/x-www-form-urlencoded"
              pawRequest.urlEncodedBody = formData
            # Set Multipart body
            else if headers['Content-Type'] == "multipart/form-data"
              pawRequest.multipartBody = formData

        return pawRequest

    @has_basic_auth = (ramlCollection, ramlRequestValue) ->
      if ramlRequestValue.security
        for security in ramlRequestValue.security
          for own key, value of security
            if ramlCollection.securityDefinitions[key] and ramlCollection.securityDefinitions[key].type == 'basic'
              return true
            break
      return false

    @json_from_definition_schema = (ramlCollection, property, indent = 0) ->

        if property.type == 'string'
            s = "\"string\""
        else if property.type == 'integer'
            s = "0"
        else if property.type == 'boolean'
            s = "true"
        else if typeof(property) == 'object'
            indent_str = Array(indent + 1).join('    ')
            indent_str_children = Array(indent + 2).join('    ')

            if property.items
              property = property.items
              s = "[\n" +
                  "#{indent_str_children}#{@json_from_definition_schema(ramlCollection, property, indent+1)}" +
                  "\n#{indent_str}]"
            else
              property = ramlCollection.definitions[property["$ref"].split('/').pop()] if property["$ref"]
              property = property.properties if property.properties # Skip properties

              s = "{\n" +
                  ("#{indent_str_children}\"#{key}\" : #{@json_from_definition_schema(ramlCollection, value, indent+1)}" for key, value of property).join(',\n') +
                  "\n#{indent_str}}"

        return s

    @createRAMLRequestUrl = (ramlCollection, ramlRequestPath, queries) ->

        # Build ramlRequestQueries
        if Object.keys(queries).length > 0
          ramlRequestQueries = []

        for key, value of queries
          ramlRequestQueries.push "#{key}=#{value}"

        ramlRequestUrl = (if ramlCollection.schemes then ramlCollection.schemes[0] else 'http') +
          '://' +
          (ramlCollection.host or 'echo.luckymarmot.com') +
          (ramlCollection.basePath or '') +
          ramlRequestPath

        if ramlRequestQueries
          ramlRequestUrl = ramlRequestUrl + '?' + ramlRequestQueries.join('&')

        return ramlRequestUrl

    @createPawGroup = (context, ramlCollection, ramlRequestPathName, ramlRequestPathValue) ->

        # Create Paw group
        pawGroup = context.createRequestGroup ramlRequestPathName

        for own ramlRequestMethod, ramlRequestValue of ramlRequestPathValue

            # Create a Paw request
            pawRequest = @createPawRequest context, ramlCollection, ramlRequestPathName, ramlRequestMethod, ramlRequestValue

            # Add request to root group
            pawGroup.appendChild pawRequest

        return pawGroup

    @importString = (context, string) ->

        try
          # Try YAML parse
          ramlCollection = yaml.load string
        catch yamlParseError
          throw new Error "Invalid RAML file format"

        if ramlCollection

          # Define host to localhost if not specified in file
          ramlCollection.host = if ramlCollection.host then ramlCollection.host else 'localhost'

          # Create a PawGroup
          pawRootGroup = context.createRequestGroup ramlCollection.info.title

          # Add RAML groups
          for own ramlRequestPathName, ramlRequestPathValue of ramlCollection.paths

            pawGroup = @createPawGroup context, ramlCollection, ramlRequestPathName, ramlRequestPathValue

            # Add group to root
            pawRootGroup.appendChild pawGroup

          return true

    return

RAMLImporter.identifier = "com.luckymarmot.PawExtensions.RAMLImporter"
RAMLImporter.title = "RAML Importer"

registerImporter RAMLImporter
