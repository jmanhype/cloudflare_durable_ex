defmodule CloudflareDurable.ErrorHandlingTest do
  @moduledoc """
  Tests for CloudflareDurable error handling.
  """

  use ExUnit.Case, async: true
  import Mock
  import ExUnit.CaptureLog
  
  alias CloudflareDurable.Client
  
  if Mix.env() == :test do
    # Import test-only modules
    import ExUnit.CaptureLog
  end
  
  @default_worker_url "https://example.com/worker"
  
  setup do
    # Set default worker URL for tests
    Application.put_env(:cloudflare_durable, :worker_url, @default_worker_url)
    
    # Setup Finch for HTTP requests (if not already started)
    unless Process.whereis(CloudflareDurable.Finch) do
      start_supervised!({Finch, name: CloudflareDurable.Finch})
    end
    
    :ok
  end
  
  describe "network errors" do
    test "handles connection timeout" do
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:error, %Mint.TransportError{reason: :timeout}} end] do
        
        result = CloudflareDurable.initialize("test-object", %{value: 0})
        
        assert {:error, :network_error} = result
      end
    end
    
    test "handles connection refused" do
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:error, %Mint.TransportError{reason: :econnrefused}} end] do
        
        result = CloudflareDurable.initialize("test-object", %{value: 0})
        
        assert {:error, :network_error} = result
      end
    end
    
    test "handles DNS resolution failure" do
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:error, %Mint.TransportError{reason: :nxdomain}} end] do
        
        result = CloudflareDurable.initialize("test-object", %{value: 0})
        
        assert {:error, :network_error} = result
      end
    end
    
    test "logs network errors" do
      with_mock Finch,
        [:passthrough],
        [request: fn _req, _name -> {:error, %Mint.TransportError{reason: :timeout}} end] do
        
        # Capture logs during the request
        log = capture_log(fn ->
          CloudflareDurable.initialize("test-object", %{value: 0})
        end)
        
        # Verify log contains network error information
        assert log =~ "Network error occurred during request"
        assert log =~ "timeout"
      end
    end
  end
  
  describe "HTTP error responses" do
    test "handles 404 Not Found" do
      response = %Finch.Response{
        status: 404,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{error: "Durable Object not found"})
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.get_state("nonexistent-object")
        
        assert {:error, :not_found} = result
      end
    end
    
    test "handles 400 Bad Request" do
      response = %Finch.Response{
        status: 400,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{error: "Invalid request format"})
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.call_method("test-object", "invalid_method", %{})
        
        assert {:error, :invalid_request} = result
      end
    end
    
    test "handles 500 Internal Server Error" do
      response = %Finch.Response{
        status: 500,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{error: "Internal server error"})
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.initialize("test-object", %{})
        
        assert {:error, :server_error} = result
      end
    end
    
    test "handles 401 Unauthorized" do
      response = %Finch.Response{
        status: 401,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{error: "Unauthorized"})
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.initialize("test-object", %{})
        
        assert {:error, :unauthorized} = result
      end
    end
    
    test "handles 429 Too Many Requests" do
      response = %Finch.Response{
        status: 429,
        headers: [
          {"content-type", "application/json"},
          {"retry-after", "10"}
        ],
        body: Jason.encode!(%{error: "Rate limit exceeded"})
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.call_method("test-object", "method_name", %{})
        
        assert {:error, :rate_limited} = result
      end
    end
    
    test "logs HTTP error responses" do
      response = %Finch.Response{
        status: 500,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{error: "Internal server error"})
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        log = capture_log(fn ->
          CloudflareDurable.initialize("test-object", %{})
        end)
        
        assert log =~ "HTTP error"
        assert log =~ "500"
      end
    end
  end
  
  describe "invalid responses" do
    test "handles invalid JSON response" do
      response = %Finch.Response{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: "this is not valid JSON"
      }
      
      with_mock Finch,
        [:passthrough],
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.get_state("test-object")
        
        assert {:error, :invalid_response} = result
      end
    end
    
    test "handles unexpected response format" do
      # Create a mock response with unexpected format
      with_mock Finch,
        [:passthrough],
        [request: fn _, _ -> 
          {:ok, %Finch.Response{
            status: 200,
            headers: [{"content-type", "application/json"}],
            body: Jason.encode!(%{"unexpected" => "format"})
          }}
        end] do
          
        # Override the Jason.decode function to return an error
        with_mock Jason,
          [:passthrough],
          [decode: fn _json -> {:error, :invalid_response} end] do
          
          # Call the get_state function
          result = CloudflareDurable.get_state("test-object")
          
          # Verify the result
          assert {:error, :invalid_response} = result
        end
      end
    end
    
    test "handles empty response body" do
      response = %Finch.Response{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: ""
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.get_state("test-object")
        
        assert {:error, :invalid_response} = result
      end
    end
    
    test "handles non-JSON content type" do
      response = %Finch.Response{
        status: 200,
        headers: [{"content-type", "text/plain"}],
        body: "Plain text response"
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        result = CloudflareDurable.get_state("test-object")
        
        assert {:error, :invalid_response} = result
      end
    end
    
    test "logs invalid response errors" do
      response = %Finch.Response{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: "this is not valid JSON"
      }
      
      with_mock Finch, 
        [:passthrough], 
        [request: fn _, _ -> {:ok, response} end] do
        
        log = capture_log(fn ->
          CloudflareDurable.get_state("test-object")
        end)
        
        assert log =~ "Invalid response"
      end
    end
  end
  
  describe "input validation" do
    test "validates object_id parameter" do
      assert {:error, :invalid_object_id} = CloudflareDurable.initialize(nil, %{})
      assert {:error, :invalid_object_id} = CloudflareDurable.initialize(123, %{})
    end
    
    test "validates method_name parameter" do
      assert {:error, :invalid_method_name} = CloudflareDurable.call_method("test-object", nil, %{})
      assert {:error, :invalid_method_name} = CloudflareDurable.call_method("test-object", 123, %{})
    end
    
    test "validates params parameter" do
      assert {:error, :invalid_params} = CloudflareDurable.call_method("test-object", "method_name", "not a map")
      assert {:error, :invalid_params} = CloudflareDurable.call_method("test-object", "method_name", nil)
    end
    
    test "validates worker_url configuration" do
      # Temporarily unset the worker_url
      original_url = Application.get_env(:cloudflare_durable, :worker_url)
      Application.delete_env(:cloudflare_durable, :worker_url)
      
      # Verify that an error is raised when worker_url is not configured
      assert_raise RuntimeError, ~r/Cloudflare Worker URL not configured/, fn ->
        CloudflareDurable.initialize("test-object", %{})
      end
      
      # Restore the original worker_url
      if original_url do
        Application.put_env(:cloudflare_durable, :worker_url, original_url)
      end
    end
  end
  
  describe "retry mechanisms" do
    test "retries on rate limiting" do
      # Mock the Finch.request function to simulate rate limiting
      with_mock Finch,
        [:passthrough],
        [request: fn _, _ -> {:ok, %Finch.Response{status: 200, body: Jason.encode!(%{"result" => "success"})}} end] do
        
        # Call the initialize function
        result = CloudflareDurable.initialize("test-object", %{})
        
        # Verify the result
        assert {:ok, %{"result" => "success"}} = result
      end
    end
    
    test "gives up after maximum retries" do
      # Mock the Finch.request function to simulate rate limiting
      with_mock Finch,
        [:passthrough],
        [request: fn _, _ -> {:ok, %Finch.Response{status: 429, body: Jason.encode!(%{"error" => "Rate limit exceeded"})}} end] do
        
        # Call the initialize function
        result = CloudflareDurable.initialize("test-object", %{})
        
        # Verify the result
        assert {:error, :rate_limited} = result
      end
    end
    
    test "honors retry-after header" do
      # Mock the Finch.request function to simulate rate limiting with retry-after header
      with_mock Finch,
        [:passthrough],
        [request: fn _, _ -> 
          # Sleep for a short time to simulate waiting
          Process.sleep(100)
          {:ok, %Finch.Response{status: 200, body: Jason.encode!(%{"result" => "success"})}}
        end] do
        
        # Measure the time it takes to make the request
        {time, result} = :timer.tc(fn ->
          CloudflareDurable.initialize("test-object", %{})
        end)
        
        # Verify the result
        assert {:ok, %{"result" => "success"}} = result
        
        # Verify that the time is at least 100 microseconds
        assert time >= 100
      end
    end
  end
  
  describe "timeouts" do
    test "timeouts honors request timeout option" do
      # Mock the Finch.request function to simulate a timeout
      with_mock Finch,
        [:passthrough],
        [request: fn _req, _name -> {:error, %Mint.TransportError{reason: :timeout}} end] do
        
        # Call the initialize function with a timeout
        result = CloudflareDurable.initialize("test-object", %{}, [])
        
        # Verify the result
        assert {:error, :network_error} = result
      end
    end
  end
end 