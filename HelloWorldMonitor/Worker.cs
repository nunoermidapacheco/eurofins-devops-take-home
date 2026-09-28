namespace HelloWorldMonitor;

public class Worker : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var url = "http://localhost:8080/HelloWorld/";
        var logFile = Path.Combine(AppContext.BaseDirectory, "status.log");
        var client = new HttpClient();      

        while (!stoppingToken.IsCancellationRequested)
        {
            int code = 0;
            string message;

            try
            {
                var response = await client.GetAsync(url);
                code = (int)response.StatusCode;
                message = response.StatusCode.ToString();
            }
            catch (Exception ex)
            {
                message = ex.Message;
            }

            File.AppendAllText(logFile, $"{DateTime.Now} | {code} | {message}{Environment.NewLine}");
            Console.WriteLine($"{DateTime.Now} | {code} | {message}");

            if (code != 200)
            {
                Environment.Exit(1);
            }

            await Task.Delay(60000, stoppingToken);
        }
    }
}