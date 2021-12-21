using ConferencesWebexScript.Entities;
using Microsoft.Extensions.Configuration;
using System;
using System.IO;

namespace ConferencesWebexScript.Helpers
{
    internal static class ScriptConfigurationHelper
    {
        private static readonly string _appSettings = "appsettings.json";
        internal static readonly string _apiUrl = @"https://demos.calltechsa.com:444/CTWeb.CiscoWH/api/wh";
        internal static readonly string _auToken = @"YXsR404cTa6/KwfwQRJBdA==";
        internal static readonly string _meetingId = "cca8c34ef77e4ce281b36d98d936d34a";
        internal static readonly string _integrationId = "12244355445";
        private static IConfiguration ConfigureSettings()
        {
            try
            {
                string ok = Directory.GetCurrentDirectory();
                IConfigurationBuilder Config = new ConfigurationBuilder().SetBasePath(Directory.GetCurrentDirectory()).AddJsonFile(_appSettings, true, true);
                return Config.Build();
            }
            catch (Exception e)
            {
                throw new Exception(e.Message, e);
            }

        }
        internal static DataCreate GetConferenceParameter()
        {
            return ScriptConfigurationHelper.ConfigureSettings().Get<DataCreate>();
        }
    }
}
